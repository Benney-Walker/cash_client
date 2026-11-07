import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

void main() {
  runApp(const CashClientApp());
}

class CashClientApp extends StatelessWidget {
  const CashClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cash Client',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // Follows the phone's setting for now. An in-app system/light/dark
      // choice needs the selection saved on the device, which is a separate
      // step.
      themeMode: ThemeMode.system,
      home: const _PlaceholderHome(),
    );
  }
}

/// Stands in until the sign-in screen exists.
class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Text('Cash Client', style: textTheme.headlineSmall),
      ),
    );
  }
}
