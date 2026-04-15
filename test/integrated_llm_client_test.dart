import 'dart:convert';

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
            contains('HTTP 404'),
          ),
        ),
      );
    },
  );

  test('falls back to the secondary volcengine endpoint after a 404', () async {
    final seenUrls = <String>[];
    final client = IntegratedLlmClient(
      client: MockClient((request) async {
        seenUrls.add(request.url.toString());
        if (request.url.toString().contains('/api/coding/v3/')) {
          return http.Response('404 page not found', 404);
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'choices': <dynamic>[
              <String, dynamic>{
                'message': <String, dynamic>{'content': 'OK'},
              },
            ],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final result = await client.completeChat(
      provider: 'volcengine',
      apiKey: 'test-key',
      model: 'ark-code-latest',
      temperature: 0,
      messages: const <Map<String, String>>[
        <String, String>{'role': 'user', 'content': 'ping'},
      ],
    );

    expect(result, 'OK');
    expect(
      seenUrls,
      contains(
        'https://ark.cn-beijing.volces.com/api/coding/v3/chat/completions',
      ),
    );
    expect(
      seenUrls,
      contains('https://ark.cn-beijing.volces.com/api/v3/chat/completions'),
    );
  });

  test('preserves provider model namespaces like meta slash llama', () async {
    late String postedModel;
    final client = IntegratedLlmClient(
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        postedModel = body['model'] as String;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'choices': <dynamic>[
              <String, dynamic>{
                'message': <String, dynamic>{'content': 'OK'},
              },
            ],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    await client.completeChat(
      provider: 'nvidia',
      apiKey: 'test-key',
      model: 'meta/llama-3.1-8b-instruct',
      temperature: 0,
      messages: const <Map<String, String>>[
        <String, String>{'role': 'user', 'content': 'ping'},
      ],
    );

    expect(postedModel, 'meta/llama-3.1-8b-instruct');
  });
}
