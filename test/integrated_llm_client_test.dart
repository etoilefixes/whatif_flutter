import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_client/src/services/backend_api_contract.dart';
import 'package:flutter_client/src/services/integrated_llm_client.dart';

void main() {
  test(
    'returns plain-text HTTP errors without throwing FormatException',
    () async {
      final client = IntegratedLlmClient(
        client: MockClient((request) async {
          return http.Response('404 page not found', 404);
        }),
      );

      expect(
        () => client.testProvider('volcengine', 'test-key'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            'HTTP 404: 404 page not found',
          ),
        ),
      );
    },
  );
}
