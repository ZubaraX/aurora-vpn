import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/local/app_paths.dart';
import 'data/local/geo_assets.dart';
import 'data/local/node_id_migration.dart';
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

  // Ship the geo rule-sets to disk before any config is generated, so smart
  // routing never has to fetch them over a network that may block it.
  await GeoAssets.unpack();

  final storage = Storage(AppPaths.dataDir());
  // Carry saved trigger profiles / zone rules / active selection across the
  // move to content-based node ids (runs before any controller reads storage).
  NodeIdMigration.run(storage);
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
