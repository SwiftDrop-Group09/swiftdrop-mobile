import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<void> deleteOwnedTemporaryProof(String path) async {
  // Resolve symlinks and verify the app cache boundary before deleting one file.
  final file = File(path);
  if (!await file.exists()) return;
  final root = await (await getTemporaryDirectory()).resolveSymbolicLinks();
  final target = await file.resolveSymbolicLinks();
  final prefix = root.endsWith(Platform.pathSeparator)
      ? root
      : '$root${Platform.pathSeparator}';
  final inside = Platform.isWindows
      ? target.toLowerCase().startsWith(prefix.toLowerCase())
      : target.startsWith(prefix);
  if (inside) await File(target).delete();
}
