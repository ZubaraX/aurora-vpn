import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/local/app_paths.dart';
import 'data/local/storage.dart';
import 'engine/engine_factory.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF111726),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  final storage = Storage(AppPaths.dataDir());
  final engine = await EngineFactory.create();

  runApp(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        engineProvider.overrideWithValue(engine),
      ],
      child: const AuroraApp(),
    ),
  );
}
