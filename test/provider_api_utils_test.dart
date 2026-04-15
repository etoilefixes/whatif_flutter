import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_client/src/models.dart';
import 'package:flutter_client/src/services/provider_api_utils.dart';

void main() {
  test('normalizes provider URLs before building the models endpoint', () {
    expect(
      normalizeProviderApiBase('https://api.openai.com/v1/chat/completions'),
      'https://api.openai.com/v1',
    );
    expect(
      buildProviderModelsUrl(
        provider: 'openai',
        customApiUrl: 'https://api.openai.com/v1/chat/completions',
      ),
      'https://api.openai.com/v1/models',
    );
    expect(
      buildProviderModelsUrl(
        provider: 'openai',
        customApiUrl: 'https://api.openai.com/v1/models',
      ),
      'https://api.openai.com/v1/models',
    );
    expect(
      buildProviderModelsUrl(
        provider: 'openai',
        customApiUrl: 'https://api.openai.com',
      ),
      'https://api.openai.com/v1/models',
    );
  });

  test('extracts model ids from common response shapes', () {
    expect(
      parseModelIdsFromResponse(<String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{'id': 'gpt-4o'},
          <String, dynamic>{'name': 'custom-name'},
          'standalone-model',
        ],
      }),
      <String>['gpt-4o', 'custom-name', 'standalone-model'],
    );

    expect(
      parseModelIdsFromResponse(<String, dynamic>{
        'result': <String, dynamic>{
          'models': <dynamic>[
            <String, dynamic>{'model': 'nested-model'},
          ],
        },
      }),
      <String>['nested-model'],
    );
  });

  test('model providers preserve enabled state across json round trips', () {
    final provider = ModelProvider(
      name: 'openai',
      apiKey: 'sk-test',
      apiUrl: 'https://api.openai.com/v1',
      models: const <String>['gpt-4o-mini'],
      enabled: false,
    );

    final decoded = ModelProvider.fromJson(provider.toJson());
    expect(decoded.enabled, isFalse);
    expect(decoded.isUsable, isFalse);
  });
}
