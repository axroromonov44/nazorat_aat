import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Console logging for HTTP traffic, in debug builds only.
///
/// Four lines per exchange — the URL, the headers and the body, for the
/// request and then for the response. The old logger drew a box around every
/// one of Dio's internal options, which pushed the one line anybody was
/// looking for off the top of the terminal.
///
/// Long values are cut short rather than wrapped: a JWT or a base64 image says
/// everything it has to say in its first few characters, and the length that
/// follows is what tells you whether it is the one you expected.
void attachDebugLogger(Dio dio, {bool logBody = true}) {
  if (!kDebugMode) return;
  dio.interceptors.add(CompactDioLogger(logBody: logBody));
}

/// Nothing at all outside debug builds: `debugPrint` writes in release too, so
/// a logger that only checks where it is called from would still talk to the
/// device log in production.
class CompactDioLogger extends Interceptor {
  CompactDioLogger({this.logBody = true});

  /// False for the catalog and tile clients, whose bodies run to megabytes.
  final bool logBody;

  static const _startKey = 'compact_log_start';
  static const _maxValue = 48;
  static const _maxBody = 400;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = DateTime.now();
    if (kDebugMode) {
      debugPrint('→ ${options.method} ${options.uri}');
      debugPrint('  h ${_headers(options.headers)}');
      if (logBody && options.data != null) {
        debugPrint('  b ${_body(options.data)}');
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (kDebugMode) {
      final options = response.requestOptions;
      debugPrint(
        '← ${response.statusCode} ${options.method} ${options.uri}'
        '${_elapsed(options)}',
      );
      debugPrint('  h ${_headers(response.headers.map)}');
      if (logBody && response.data != null) {
        debugPrint('  b ${_body(response.data)}');
      }
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      final options = err.requestOptions;
      final status = err.response?.statusCode;
      debugPrint(
        '✗ ${status ?? err.type.name} ${options.method} ${options.uri}'
        '${_elapsed(options)}',
      );
      final data = err.response?.data;
      if (data != null) debugPrint('  b ${_body(data)}');
    }
    handler.next(err);
  }

  String _headers(Map<String, dynamic> headers) {
    if (headers.isEmpty) return '{}';
    final parts = headers.entries.map((e) {
      final value = e.value is List
          ? (e.value as List).join(', ')
          : '${e.value}';
      return '${e.key}: ${_clip(value, _maxValue)}';
    });
    return '{${parts.join(', ')}}';
  }

  String _body(Object? data) {
    if (data is FormData) {
      // A multipart body has no useful `toString`; its parts are what matter.
      final fields = data.fields.map(
        (f) => '${f.key}=${_clip(f.value, _maxValue)}',
      );
      final files = data.files.map((f) => '${f.key}=<${f.value.length} bytes>');
      return '{${[...fields, ...files].join(', ')}}';
    }
    final text = data is String ? data : _encode(data);
    return _clip(text, _maxBody);
  }

  String _encode(Object? data) {
    try {
      return jsonEncode(data);
    } catch (_) {
      return '$data';
    }
  }

  String _clip(String value, int max) {
    final flat = value.replaceAll('\n', ' ');
    if (flat.length <= max) return flat;
    return '${flat.substring(0, max)}…(${flat.length})';
  }

  String _elapsed(RequestOptions options) {
    final start = options.extra[_startKey];
    if (start is! DateTime) return '';
    return ' ${DateTime.now().difference(start).inMilliseconds}ms';
  }
}
