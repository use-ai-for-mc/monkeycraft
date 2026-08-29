import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

bool localFileExists(String path) => File(path).existsSync();

Future<String?> persistLocalFile(String sourcePath, String destName) async {
  final dir = await getApplicationDocumentsDirectory();
  final dest = File('${dir.path}/$destName');
  await File(sourcePath).copy(dest.path);
  return dest.path;
}

Future<void> deleteLocalFile(String path) async {
  final file = File(path);
  if (file.existsSync()) {
    await file.delete();
  }
}

Widget? localFileImage(String path, {BoxFit fit = BoxFit.cover}) {
  return Image.file(
    File(path),
    fit: fit,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );
}
