import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_client/main.dart';
import 'package:flutter_client/src/app_controller.dart';
import 'package:flutter_client/src/l10n/app_strings.dart';
import 'package:flutter_client/src/services/api_client.dart';
import 'package:flutter_client/src/services/config_store.dart';

void main() {
  testWidgets('renders loading shell before initialization completes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final controller = AppController(
      store: ConfigStore(preferences),
      api: ApiClient(),
    );

    await tester.pumpWidget(WhatIfApp(controller: controller));

    expect(find.text(AppStrings('zh-CN').text('app.loading')), findsOneWidget);
  });
}
