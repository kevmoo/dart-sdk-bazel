// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:analyzer/src/util/platform_info.dart';
import 'package:path/path.dart' as path;

/// Return the path to the runtime Dart SDK.
String getSdkPath() {
  var executableDir = path.dirname(platform.resolvedExecutable);
  var cwd = Directory.current.path;

  var candidates = <String>[];

  var runFiles = Platform.environment['TEST_SRCDIR'];
  if (runFiles != null) {
    candidates.addAll([
      path.join(runFiles, '_main', 'sdk'),
      path.join(runFiles, 'sdk'),
      path.join(runFiles, 'prebuilt_dart_sdk'),
      path.join(runFiles, '_main', 'external', 'prebuilt_dart_sdk'),
      path.join(runFiles, '+third_party_extension+prebuilt_dart_sdk'),
    ]);
  }

  candidates.addAll([
    path.join(executableDir, 'dart-sdk'),
    path.dirname(executableDir),
    executableDir,
    path.join(cwd, 'third_party', 'dart_lang', 'v2', 'sdk'),
    path.join(cwd, 'third_party', 'dart_lang', 'macos_sdk'),
    path.join(executableDir, 'third_party', 'dart_lang', 'v2', 'sdk'),
    path.join(
      path.dirname(executableDir),
      'third_party',
      'dart_lang',
      'v2',
      'sdk',
    ),
  ]);

  for (var candidate in candidates) {
    if (File(
          path.join(candidate, 'lib', '_internal', 'allowed_experiments.json'),
        ).existsSync() ||
        File(path.join(candidate, 'lib', 'libraries.json')).existsSync() ||
        Directory(path.join(candidate, 'lib', '_internal')).existsSync()) {
      return candidate;
    }
  }

  return path.dirname(executableDir);
}
