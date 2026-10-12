import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'karantin_face_config.dart';
import 'karantin_face_exception.dart';
import 'karantin_face_session.dart';

/// A captured face payload ready to upload: the primary (cropped) image plus up
/// to four additional "check" frames.
class KarantinFacePayload {
  const KarantinFacePayload(
      {required this.faceImage, required this.checkImages});

  final Uint8List faceImage;
  final List<Uint8List> checkImages;
}

/// Native client for the Karantin ID OAuth endpoints under `<baseUrl>/app`.
///
/// Fetches the session token from `authorize`, submits the face verification
/// multipart request, and follows the resulting redirect chain until the `code`
/// lands on the configured redirect URI.
class KarantinFaceRemoteDataSource {
  KarantinFaceRemoteDataSource({
    required KarantinFaceConfig config,
    Dio? dio,
    Dio? redirectDio,
    CookieJar? cookieJar,
  })  : _config = config,
        _cookieJar = cookieJar ?? CookieJar(),
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: config.apiBaseUrl,
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 30),
                sendTimeout: const Duration(seconds: 30),
                headers: {'Accept-Language': 'uz'},
              ),
            ),
        _redirectDio = redirectDio ??
            Dio(
              BaseOptions(
                followRedirects: false,
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 30),
                validateStatus: (status) => status != null && status < 400,
              ),
            ) {
    _dio.interceptors.add(CookieManager(_cookieJar));
    _redirectDio.interceptors.add(CookieManager(_cookieJar));

    if (config.debugLogging) {
      _dio.interceptors
          .add(LogInterceptor(requestBody: true, responseBody: true));
      _redirectDio.interceptors.add(LogInterceptor());
    }
  }

  final KarantinFaceConfig _config;
  final CookieJar _cookieJar;
  final Dio _dio;
  final Dio _redirectDio;

  static const int _maxRedirects = 10;

  /// Hits `authorize` and parses the SPA route it redirects to, yielding the
  /// token/name (login, verify-document) or code/state (register).
  Future<KarantinFaceSession> startSession() async {
    final Response response;
    try {
      response = await _redirectDio.getUri<void>(_config.authorizeUri);
    } on DioException catch (e) {
      throw KarantinFaceException(
        'Karantin ID bilan bogʻlanib boʻlmadi. Qayta urinib koʻring.',
        statusCode: e.response?.statusCode,
      );
    }

    final location = _locationHeader(response);
    if (location == null) {
      throw const KarantinFaceException(
          'Karantin ID sessiyasini ochib boʻlmadi.');
    }

    final uri = _resolve(location);
    final query = uri.queryParameters;
    final path = uri.path;

    if (_config.debugLogging) {
      final stored = await _cookieJar.loadForRequest(
        Uri.parse(_config.apiBaseUrl),
      );
      debugPrint('[KarantinFace] authorize -> $uri');
      debugPrint(
        '[KarantinFace]   session cookies: '
        '${stored.isEmpty ? '(none)' : stored.map((c) => c.name).join(', ')}',
      );
    }

    if (path.contains('sign-up')) {
      return KarantinFaceSession(
        flow: KarantinFaceFlow.register,
        code: query['code'],
        state: query['state'],
        name: query['name'],
      );
    }
    if (path.contains('verify-document')) {
      return KarantinFaceSession(
        flow: KarantinFaceFlow.verifyDocument,
        token: query['token'],
        name: query['name'],
      );
    }
    return KarantinFaceSession(
      flow: KarantinFaceFlow.login,
      token: query['token'],
      name: query['name'],
    );
  }

  /// Notifies the backend which identifier is attempting login before the face
  /// scan. Best-effort: failures here must not block the scan.
  Future<void> notifyLogin({
    required String token,
    required String passportNumber,
  }) async {
    try {
      await _dio.post<void>(
        '/project/notify/login/',
        data: {'token': token, 'passport_number': passportNumber},
      );
    } on DioException {
      // Non-fatal.
    }
  }

  Future<String> submitLogin({
    required String token,
    required String identifier,
    required bool isPnfl,
    required bool includeScreens,
    required KarantinFacePayload payload,
    required Map<String, String> deviceFields,
  }) {
    return _submitFace(
      '/project/oauth/login',
      payload: payload,
      includeScreens: includeScreens,
      deviceFields: deviceFields,
      fields: {
        isPnfl ? 'pinfl' : 'passport_number': identifier,
        'token': token
      },
    );
  }

  Future<String> submitRegister({
    required String oneCode,
    required String? token,
    required bool includeScreens,
    required KarantinFacePayload payload,
    required Map<String, String> deviceFields,
  }) {
    return _submitFace(
      '/project/oauth/register',
      payload: payload,
      includeScreens: includeScreens,
      deviceFields: deviceFields,
      fields: {'one_code': oneCode, if (token != null) 'token': token},
    );
  }

  Future<String> submitVerifyDocument({
    required String token,
    required bool includeScreens,
    required KarantinFacePayload payload,
    required Map<String, String> deviceFields,
  }) {
    return _submitFace(
      '/project/oauth/verify-doc',
      payload: payload,
      includeScreens: includeScreens,
      deviceFields: deviceFields,
      fields: {'token': token},
    );
  }

  Future<String> _submitFace(
    String path, {
    required KarantinFacePayload payload,
    required bool includeScreens,
    required Map<String, String> deviceFields,
    required Map<String, String> fields,
  }) async {
    final form = FormData();

    deviceFields.forEach((key, value) {
      if (value.isNotEmpty) form.fields.add(MapEntry(key, value));
    });
    fields.forEach((key, value) {
      if (value.isNotEmpty) form.fields.add(MapEntry(key, value));
    });

    form.files.add(
      MapEntry(
        'face_image',
        MultipartFile.fromBytes(
          payload.faceImage,
          filename: 'user.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      ),
    );

    if (includeScreens) {
      final screens = payload.checkImages.take(4).toList();
      for (var i = 0; i < screens.length; i++) {
        form.files.add(
          MapEntry(
            'check_image${i + 1}',
            MultipartFile.fromBytes(
              screens[i],
              filename: 'additional-${i + 1}-image.jpg',
              contentType: DioMediaType('image', 'jpeg'),
            ),
          ),
        );
      }
    }

    if (_config.debugLogging) await _logFormData(path, form);

    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(path, data: form);
    } on DioException catch (e) {
      throw KarantinFaceException(
        _faceErrorMessage(e),
        statusCode: e.response?.statusCode,
      );
    }

    final redirectTo = response.data?['redirect_to'];
    if (redirectTo is! String || redirectTo.isEmpty) {
      throw const KarantinFaceException(
          'Serverdan yoʻnaltirish manzili kelmadi.');
    }
    return redirectTo;
  }

  /// Dio's own logger prints a multipart body as `Instance of 'FormData'`, so
  /// a rejected submit says nothing about what was sent. This spells out every
  /// field, every file and the cookies that went with them.
  Future<void> _logFormData(String path, FormData form) async {
    final uri = Uri.parse('${_config.apiBaseUrl}$path');
    final cookies = await _cookieJar.loadForRequest(uri);

    debugPrint('[KarantinFace] POST $uri');
    for (final field in form.fields) {
      debugPrint('[KarantinFace]   field ${field.key} = ${field.value}');
    }
    for (final file in form.files) {
      debugPrint(
        '[KarantinFace]   file ${file.key} = '
        '${file.value.filename} (${file.value.length} bytes)',
      );
    }
    debugPrint(
      '[KarantinFace]   cookies: '
      '${cookies.isEmpty ? '(none)' : cookies.map((c) => '${c.name}=${c.value}').join('; ')}',
    );
  }

  /// Walks the redirect chain starting at [redirectTo] until it reaches the
  /// configured redirect URI and returns its `code` query parameter.
  Future<String> followToCode(String redirectTo) async {
    var current = _resolve(redirectTo);

    for (var i = 0; i < _maxRedirects; i++) {
      if (current.toString().startsWith(_config.redirectUri)) {
        final code = current.queryParameters['code'];
        if (code != null && code.isNotEmpty) return code;
        throw const KarantinFaceException('Yakuniy manzilda kod topilmadi.');
      }

      final Response response;
      try {
        response = await _redirectDio.getUri<void>(current);
      } on DioException catch (e) {
        throw KarantinFaceException(
          'Yoʻnaltirishni kuzatib boʻlmadi.',
          statusCode: e.response?.statusCode,
        );
      }

      final location = _locationHeader(response);
      if (location == null) {
        final finalUri = response.realUri;
        if (finalUri.toString().startsWith(_config.redirectUri)) {
          final code = finalUri.queryParameters['code'];
          if (code != null && code.isNotEmpty) return code;
        }
        throw const KarantinFaceException(
            'Avtorizatsiya kodini olib boʻlmadi.');
      }

      current = _resolve(location, base: current);
    }

    throw const KarantinFaceException(
        'Juda koʻp yoʻnaltirish. Qayta urinib koʻring.');
  }

  String? _locationHeader(Response response) {
    final status = response.statusCode ?? 0;
    if (status < 300 || status >= 400) return null;
    final location = response.headers.value('location');
    if (location == null || location.isEmpty) return null;
    return location;
  }

  Uri _resolve(String location, {Uri? base}) {
    final uri = Uri.parse(location);
    if (uri.hasScheme) return uri;
    final root = base ?? Uri.parse(_config.baseUrl);
    return root.resolveUri(uri);
  }

  String _faceErrorMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      final errors = data['errors'];
      if (errors is List && errors.isNotEmpty) {
        final first = errors.first;
        if (first is Map && first['message'] is String) {
          return first['message'] as String;
        }
      }
    }
    return 'Yuzni tasdiqlab boʻlmadi. Qaytadan urinib koʻring.';
  }
}
