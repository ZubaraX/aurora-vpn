import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/shell/root_shell.dart';

class AuroraApp extends StatelessWidget {
  const AuroraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aurora',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const RootShell(),
    );
  }
}
