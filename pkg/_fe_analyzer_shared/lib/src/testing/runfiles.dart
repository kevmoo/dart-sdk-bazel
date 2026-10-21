// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

/// Encapsulates dual-mode test resource resolution.
Uri resolveTestResource(String runfilesPath, {Uri? baseUri}) {
  final normalizedRunfilesPath = runfilesPath.trim().replaceAll('\\', '/');

  final manifestFile = Platform.environment['RUNFILES_MANIFEST_FILE'];
  if (manifestFile != null && manifestFile.isNotEmpty) {
    final resolved = _RunfilesManifest.resolve(
      manifestFile,
      normalizedRunfilesPath,
    );
    if (resolved != null) {
      if (FileSystemEntity.isDirectorySync(resolved)) {
        return Uri.directory(resolved);
      }
      return Uri.file(resolved);
    }
  }

  final runfilesDir =
      Platform.environment['RUNFILES_DIR'] ??
      Platform.environment['TEST_SRCDIR'];
  if (runfilesDir != null && runfilesDir.isNotEmpty) {
    final candidatePaths = [
      '_main/$normalizedRunfilesPath',
      normalizedRunfilesPath,
      '+dart_packages_extension+dart_packages/$normalizedRunfilesPath',
      'dart_packages/$normalizedRunfilesPath',
    ];
    for (final candidate in candidatePaths) {
      final path = '$runfilesDir/$candidate';
      final fileOrDir = FileSystemEntity.typeSync(path);
      if (fileOrDir != FileSystemEntityType.notFound) {
        if (fileOrDir == FileSystemEntityType.directory) {
          return Uri.directory(path);
        } else {
          return Uri.file(path);
        }
      }
    }
  }

  final scriptUri = baseUri ?? Platform.script;
  final scriptPath = scriptUri.path;
  final pkgIndex = scriptPath.lastIndexOf('/pkg/');
  if (pkgIndex != -1) {
    final repoRootPath = scriptPath.substring(0, pkgIndex + 1);
    final repoRootUri = scriptUri.replace(path: repoRootPath);
    final candidateUri = repoRootUri.resolve(normalizedRunfilesPath);
    if (candidateUri.scheme == 'file') {
      final fileOrDir = FileSystemEntity.typeSync(candidateUri.toFilePath());
      if (fileOrDir != FileSystemEntityType.notFound) {
        return candidateUri;
      }
    }
  }

  var curr = scriptUri.resolve('.');
  while (curr.path.length > 1) {
    final candidateUri = curr.resolve(normalizedRunfilesPath);
    if (candidateUri.scheme == 'file') {
      final fileOrDir = FileSystemEntity.typeSync(candidateUri.toFilePath());
      if (fileOrDir != FileSystemEntityType.notFound) {
        return candidateUri;
      }
    }
    final parent = curr.resolve('..');
    if (parent == curr) break;
    curr = parent;
  }

  return scriptUri.resolve(normalizedRunfilesPath);
}

abstract final class _RunfilesManifest {
  static Map<String, String>? _manifest;
  static String? _loadedManifestPath;

  static String? resolve(String manifestPath, String runfilesPath) {
    if (_loadedManifestPath != manifestPath) {
      _manifest = _loadManifest(manifestPath);
      _loadedManifestPath = manifestPath;
    }
    final candidatePaths = ['_main/$runfilesPath', runfilesPath];
    for (final candidate in candidatePaths) {
      final resolved = _manifest![candidate];
      if (resolved != null) {
        return resolved;
      }
    }
    return null;
  }

  static Map<String, String> _loadManifest(String path) {
    final map = <String, String>{};
    final file = File(path);
    if (file.existsSync()) {
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final spaceIndex = trimmed.indexOf(' ');
        if (spaceIndex != -1) {
          final manifestPath = trimmed.substring(0, spaceIndex);
          final physicalPath = trimmed.substring(spaceIndex + 1);
          map[manifestPath] = physicalPath;
        }
      }
    }
    return map;
  }
}
