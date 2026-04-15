import 'dart:collection';

import '../models.dart';

String? normalizeProviderApiBase(String? value) {
  if (value == null) {
    return null;
  }

  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final uri = Uri.parse(trimmed);
  var path = uri.path.replaceAll(RegExp(r'/+$'), '');

  const resourceSuffixes = <String>[
    '/chat/completions',
    '/responses',
    '/models',
    '/completions',
    '/embeddings',
    '/messages',
  ];

  var changed = true;
  while (changed && path.isNotEmpty) {
    changed = false;
    for (final suffix in resourceSuffixes) {
      if (!path.endsWith(suffix)) {
        continue;
      }
      path = path.substring(0, path.length - suffix.length);
      path = path.replaceAll(RegExp(r'/+$'), '');
      changed = true;
      break;
    }
  }

  final normalized = uri
      .replace(path: path.isEmpty ? '' : path, query: null, fragment: null)
      .toString();

  return normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
}

String? resolveProviderApiBase({
  required String provider,
  String? customApiUrl,
}) {
  final provided = customApiUrl?.trim();
  final normalizedCustom = normalizeProviderApiBase(provided);
  if (normalizedCustom != null) {
    return _completeKnownOfficialBase(
      provider: provider,
      normalizedBase: normalizedCustom,
    );
  }

  return normalizeProviderApiBase(
    ModelProvider.defaultApiUrls[provider.toLowerCase()],
  );
}

String buildProviderModelsUrl({
  required String provider,
  String? customApiUrl,
}) {
  final baseUrl = resolveProviderApiBase(
    provider: provider,
    customApiUrl: customApiUrl,
  );
  if (baseUrl == null || baseUrl.isEmpty) {
    throw StateError('Unable to resolve a provider base URL.');
  }

  final uri = Uri.parse(baseUrl);
  final path = uri.path.replaceAll(RegExp(r'/+$'), '');
  final modelsPath = path.isEmpty ? '/v1/models' : '$path/models';
  return uri.replace(path: modelsPath, query: null, fragment: null).toString();
}

Map<String, String> buildProviderHeaders({
  required String provider,
  required String apiKey,
}) {
  final headers = <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  final trimmedKey = apiKey.trim();
  if (trimmedKey.isEmpty) {
    return headers;
  }

  if (provider.toLowerCase() == 'anthropic') {
    headers['x-api-key'] = trimmedKey;
    headers['anthropic-version'] = '2023-06-01';
  } else {
    headers['Authorization'] = 'Bearer $trimmedKey';
  }

  return headers;
}

List<String> parseModelIdsFromResponse(Object? response) {
  final modelIds = LinkedHashSet<String>();

  void addCandidate(Object? candidate) {
    final value = candidate?.toString().trim() ?? '';
    if (value.isEmpty) {
      return;
    }
    modelIds.add(value);
  }

  void visitList(List<dynamic> items) {
    for (final item in items) {
      if (item is String) {
        addCandidate(item);
        continue;
      }

      if (item is! Map) {
        continue;
      }

      addCandidate(item['id']);
      addCandidate(item['model']);
      addCandidate(item['name']);
    }
  }

  void visitNode(Object? node) {
    if (node is List<dynamic>) {
      visitList(node);
      return;
    }

    if (node is! Map) {
      return;
    }

    visitNode(node['data']);
    visitNode(node['models']);
    visitNode(node['items']);
    visitNode(node['result']);
  }

  visitNode(response);
  return modelIds.toList(growable: false);
}

String _completeKnownOfficialBase({
  required String provider,
  required String normalizedBase,
}) {
  final uri = Uri.parse(normalizedBase);
  final path = uri.path.replaceAll(RegExp(r'/+$'), '');
  if (path.isNotEmpty) {
    return normalizedBase;
  }

  final host = uri.host.toLowerCase();
  final providerKey = provider.toLowerCase();
  String? officialPath;

  if (providerKey == 'openai' && host == 'api.openai.com') {
    officialPath = '/v1';
  } else if (providerKey == 'anthropic' && host == 'api.anthropic.com') {
    officialPath = '/v1';
  } else if (providerKey == 'gemini' &&
      host == 'generativelanguage.googleapis.com') {
    officialPath = '/v1beta/openai';
  } else if (providerKey == 'dashscope' &&
      host == 'dashscope.aliyuncs.com') {
    officialPath = '/compatible-mode/v1';
  } else if (providerKey == 'volcengine' && host.endsWith('.volces.com')) {
    officialPath = '/api/v3';
  } else if (providerKey == 'nvidia' &&
      host == 'integrate.api.nvidia.com') {
    officialPath = '/v1';
  }

  if (officialPath == null) {
    return normalizedBase;
  }

  return uri.replace(path: officialPath, query: null, fragment: null).toString();
}
