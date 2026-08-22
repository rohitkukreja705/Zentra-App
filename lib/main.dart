import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'features/shell/main_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZentraApp());
}

class ZentraApp extends StatelessWidget {
  const ZentraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zentra',
      debugShowCheckedModeBanner: false,
      theme: buildZentraTheme(),
      home: const MainShell(),
    );
  }
}
