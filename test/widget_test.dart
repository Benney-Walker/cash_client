import 'package:cash_client/main.dart';
import 'package:cash_client/theme/app_status_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app starts with the light theme on a light device',
      (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(const CashClientApp());

    final context = tester.element(find.text('Cash Client'));
    expect(Theme.of(context).brightness, Brightness.light);
    expect(AppStatusColors.of(context), AppStatusColors.light);
  });

  testWidgets('app follows the device into dark mode', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(const CashClientApp());

    final context = tester.element(find.text('Cash Client'));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(AppStatusColors.of(context), AppStatusColors.dark);
  });
}
