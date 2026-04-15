import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_client/src/services/backend_api_contract.dart';
import 'package:flutter_client/src/services/integrated_llm_client.dart';
import 'package:flutter_client/src/models.dart';

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

  test(
    'recovers nvidia 404s by probing models and retrying with an available model',
    () async {
      final seenUrls = <String>[];
      final postedModels = <String>[];
      final client = IntegratedLlmClient(
        client: MockClient((request) async {
          seenUrls.add(request.url.toString());
          if (request.method == 'POST') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            postedModels.add(body['model'] as String);
          }

          if (request.url.toString() ==
              'https://integrate.api.nvidia.com/v1/chat/completions') {
            if (postedModels.length == 1) {
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
              headers: const <String, String>{
                'content-type': 'application/json',
              },
            );
          }

          if (request.url.toString() ==
              'https://integrate.api.nvidia.com/v1/models') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'data': <dynamic>[
                  <String, dynamic>{
                    'id': 'nvidia/llama-3.1-nemotron-nano-8b-v1',
                  },
                ],
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json',
              },
            );
          }

          return http.Response('not found', 404);
        }),
      );

      final result = await client.completeChat(
        provider: 'nvidia',
        apiKey: 'test-key',
        model: 'meta/llama-3.1-8b-instruct',
        temperature: 0,
        messages: const <Map<String, String>>[
          <String, String>{'role': 'user', 'content': 'ping'},
        ],
      );

      expect(result, 'OK');
      expect(seenUrls, contains('https://integrate.api.nvidia.com/v1/models'));
      expect(postedModels, <String>[
        'meta/llama-3.1-8b-instruct',
        'nvidia/llama-3.1-nemotron-nano-8b-v1',
      ]);
    },
  );

  test('nvidia defaults prefer the first-party nemotron model', () {
    expect(
      ModelProvider.suggestedModelsFor('nvidia').first,
      'nvidia/llama-3.1-nemotron-nano-8b-v1',
    );
  });
}
