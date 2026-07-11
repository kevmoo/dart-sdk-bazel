// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' show Directory, Platform;
import 'package:analyzer/src/util/platform_info.dart';
import 'package:path/path.dart' as path;

/// Return the path to the runtime Dart SDK.
String getSdkPath() {
  var defaultPath = path.dirname(path.dirname(platform.resolvedExecutable));
  // If the default path looks like an SDK (it has lib/_internal), use it.
  if (Directory(path.join(defaultPath, 'lib', '_internal')).existsSync()) {
    return defaultPath;
  }
  // In a Bazel environment, the executable might be runtime/bin/dartvm,
  // whose parent directory is not an SDK directory.
  var runFiles = Platform.environment['TEST_SRCDIR'];
  if (runFiles != null) {
    for (var candidate in [
      path.join(runFiles, '_main', 'sdk'),
      path.join(runFiles, 'sdk'),
      path.join(runFiles, 'prebuilt_dart_sdk'),
      path.join(runFiles, '_main', 'external', 'prebuilt_dart_sdk'),
      path.join(runFiles, '+third_party_extension+prebuilt_dart_sdk'),
    ]) {
      if (Directory(path.join(candidate, 'lib', '_internal')).existsSync()) {
        return candidate;
      }
    }
  }
  return defaultPath;
}
