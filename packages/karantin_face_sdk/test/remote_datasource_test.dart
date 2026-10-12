import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karantin_face_sdk/src/karantin_face_config.dart';
import 'package:karantin_face_sdk/src/karantin_face_remote_datasource.dart';

class _MarkerInterceptor extends Interceptor {}

void main() {
  const config = KarantinFaceConfig(
    clientId: 'test_client',
    redirectUri: 'https://example.invalid/callback',
  );

  group('KarantinFaceRemoteDataSource', () {
    test("the host's interceptors reach both clients", () {
      final marker = _MarkerInterceptor();
      final dio = Dio();
      final redirectDio = Dio();

      KarantinFaceRemoteDataSource(
        config: KarantinFaceConfig(
          clientId: 'test_client',
          redirectUri: 'https://example.invalid/callback',
          interceptors: [marker],
        ),
        dio: dio,
        redirectDio: redirectDio,
      );

      // The redirect client is the one that walks the 302 chain, so leaving it
      // out would hide exactly the half of the flow that is hardest to guess.
      expect(dio.interceptors, contains(marker));
      expect(redirectDio.interceptors, contains(marker));
    });

    test('the authorize URL carries the OAuth parameters', () {
      final uri = config.authorizeUri;

      expect(uri.origin, 'https://id.karantin.uz');
      expect(uri.path, '/app/project/oauth/authorize');
      expect(uri.queryParameters['client_id'], 'test_client');
      expect(
        uri.queryParameters['redirect_uri'],
        'https://example.invalid/callback',
      );
      expect(config.apiBaseUrl, 'https://id.karantin.uz/app');
    });
  });
}
