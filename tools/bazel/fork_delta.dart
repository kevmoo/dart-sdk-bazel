// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'cli_utils.dart';

const usage = '''
fork_delta.dart: Trivial delta inspection tool between the long-running Bazel fork and upstream Dart SDK.

Usage:
  dart tools/bazel/fork_delta.dart [options]

Options:
  --summary            Display a scannable summary of categorized delta files (default).
  --upstream-cl        Display precisely the non-Bazel Dart SDK files modified/deleted to form an upstream CL.
  --diff <category>    Display the Git diff for a specific category or file.
  --json               Generate structured JSON output for programmatic consumption by AI agents.
  --base <ref>         Override the upstream tracking reference (defaults to official/main).
  --help, -h           Show this help message.

Categories:
  - bazel-infra       (Added BUILD.bazel, .bzl, WORKSPACE, MODULE.bazel files)
  - agent-meta        (Added .agents/, .beads/, docs/ tracking files)
  - added-other       (Other added source files)
  - modified-cpp-gn   (Modified upstream runtime/ C++ and GN files)
  - modified-dart     (Modified upstream pkg/, tests/, utils/ Dart code)
  - modified-tools    (Modified upstream tools/, scripts, PRESUBMIT.py)
  - modified-other    (Other modified upstream files)
  - deleted           (Deleted or masked upstream files)
''';

void main(List<String> args) => runCli(() => _main(args));

void _main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    print(usage);
    return;
  }

  final isJson = args.contains('--json');
  String? upstreamRef;
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--base' && i + 1 < args.length) {
      upstreamRef = args[i + 1];
    }
  }

  String? diffCategory;
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--diff' && i + 1 < args.length) {
      diffCategory = args[i + 1];
    }
  }

  // Locate the Git database
  final gitDir = await runGit(['rev-parse', '--git-dir']);
  if (gitDir == null) {
    _error('Fatal: Not inside a valid Git repository.', isJson);
    return;
  }

  // Auto-detect upstream reference if not explicitly overridden via --base
  if (upstreamRef == null) {
    final candidates = [
      'upstream-sdk/main',
      'upstream/main',
      'official/main',
      'dart-googlesource/main'
    ];
    for (final cand in candidates) {
      final check = await getGitMergeBase(cand, 'HEAD');
      if (check != null && check.isNotEmpty) {
        upstreamRef = cand;
        break;
      }
    }
    upstreamRef ??= 'official/main';
  }

  // Find the merge base with upstream Ref
  final mergeBase = await getGitMergeBase(upstreamRef, 'HEAD');
  if (mergeBase == null) {
    _error(
        'Fatal: Could not find merge base between $upstreamRef and HEAD. Make sure official remote is fetched.',
        isJson);
    return;
  }

  // Retrieve both name-status and numstat deltas
  final diffStatus = await runGit(['diff', '--name-status', mergeBase, 'HEAD']);
  final diffNumstat = await runGit(['diff', '--numstat', mergeBase, 'HEAD']);
  if (diffStatus == null || diffNumstat == null) {
    _error('Fatal: Failed to run git diff against $mergeBase.', isJson);
    return;
  }

  // Parse numstat map: path -> (insertions, deletions)
  final numstatMap = <String, ({int added, int deleted})>{};
  for (final line in diffNumstat.trim().split('\n')) {
    if (line.trim().isEmpty) continue;
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length >= 3) {
      final added = int.tryParse(parts[0]) ?? 0;
      final deleted = int.tryParse(parts[1]) ?? 0;
      final path = parts.sublist(2).join(' ');
      numstatMap[path] = (added: added, deleted: deleted);
    }
  }

  final lines = diffStatus.trim().split('\n');
  final delta = Delta(mergeBase: mergeBase, head: 'HEAD');

  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final parts = line.split(RegExp(r'\s+'));
    final status = parts[0];
    final path = parts.length > 2 && status.startsWith('R')
        ? parts[2]
        : parts.sublist(1).join(' ');

    final stats = numstatMap[path] ?? (added: 0, deleted: 0);
    final fileEntry = FileStat(path, stats.added, stats.deleted);

    if (status.startsWith('D')) {
      if (_isSafeDeleted(path)) {
        delta.safeDeleted.add(fileEntry);
      } else {
        delta.actionableDeleted.add(fileEntry);
      }
    } else if (status.startsWith('A')) {
      if (_isBazelInfra(path)) {
        delta.bazelInfra.add(fileEntry);
      } else if (_isAgentMeta(path)) {
        delta.agentMeta.add(fileEntry);
      } else {
        delta.addedOther.add(fileEntry);
      }
    } else if (status.startsWith('M') || status.startsWith('R')) {
      if (_isCppOrGn(path)) {
        delta.modifiedCppGn.add(fileEntry);
      } else if (_isDartCode(path)) {
        delta.modifiedDart.add(fileEntry);
      } else if (_isToolScript(path)) {
        delta.modifiedTools.add(fileEntry);
      } else {
        delta.modifiedOther.add(fileEntry);
      }
    }
  }

  if (diffCategory != null) {
    await _printDiff(diffCategory, delta, mergeBase, isJson);
    return;
  }

  if (args.contains('--upstream-cl')) {
    if (isJson) {
      print(jsonEncode({
        'merge_base': mergeBase,
        'upstream_cl_candidates': {
          'modified': [
            ...delta.modifiedCppGn.map((e) => e.toJson()),
            ...delta.modifiedDart.map((e) => e.toJson()),
            ...delta.modifiedTools.map((e) => e.toJson()),
            ...delta.modifiedOther.map((e) => e.toJson())
          ],
          'deleted': delta.actionableDeleted.map((e) => e.toJson()).toList(),
          'total_lines': {
            'added': delta.upstreamModifiedInsertions,
            'deleted': delta.upstreamModifiedDeletions,
          }
        }
      }));
    } else {
      _printUpstreamCl(delta, upstreamRef);
    }
    return;
  }

  if (isJson) {
    print(jsonEncode(delta.toJson()));
  } else {
    _printHumanSummary(delta, upstreamRef);
  }
}

class FileStat {
  final String path;
  final int added;
  final int deleted;

  FileStat(this.path, this.added, this.deleted);

  Map<String, dynamic> toJson() => {
        'path': path,
        'added': added,
        'deleted': deleted,
      };

  @override
  String toString() =>
      added == 0 && deleted == 0 ? path : '$path (+$added, -$deleted)';
}

class Delta {
  final String mergeBase;
  final String head;

  final List<FileStat> bazelInfra = [];
  final List<FileStat> agentMeta = [];
  final List<FileStat> addedOther = [];
  final List<FileStat> modifiedCppGn = [];
  final List<FileStat> modifiedDart = [];
  final List<FileStat> modifiedTools = [];
  final List<FileStat> modifiedOther = [];
  final List<FileStat> safeDeleted = [];
  final List<FileStat> actionableDeleted = [];

  Delta({required this.mergeBase, required this.head});

  int get totalAddedFiles =>
      bazelInfra.length + agentMeta.length + addedOther.length;
  int get totalModifiedFiles =>
      modifiedCppGn.length +
      modifiedDart.length +
      modifiedTools.length +
      modifiedOther.length;
  int get totalDeletedFiles => safeDeleted.length + actionableDeleted.length;

  int _sumAdded(List<FileStat> list) =>
      list.fold(0, (sum, item) => sum + item.added);
  int _sumDeleted(List<FileStat> list) =>
      list.fold(0, (sum, item) => sum + item.deleted);

  int get totalInsertions =>
      _sumAdded(bazelInfra) +
      _sumAdded(agentMeta) +
      _sumAdded(addedOther) +
      _sumAdded(modifiedCppGn) +
      _sumAdded(modifiedDart) +
      _sumAdded(modifiedTools) +
      _sumAdded(modifiedOther);

  int get totalDeletions =>
      _sumDeleted(bazelInfra) +
      _sumDeleted(agentMeta) +
      _sumDeleted(addedOther) +
      _sumDeleted(modifiedCppGn) +
      _sumDeleted(modifiedDart) +
      _sumDeleted(modifiedTools) +
      _sumDeleted(modifiedOther) +
      _sumDeleted(safeDeleted) +
      _sumDeleted(actionableDeleted);

  int get upstreamModifiedInsertions =>
      _sumAdded(modifiedCppGn) +
      _sumAdded(modifiedDart) +
      _sumAdded(modifiedTools) +
      _sumAdded(modifiedOther);

  int get upstreamModifiedDeletions =>
      _sumDeleted(modifiedCppGn) +
      _sumDeleted(modifiedDart) +
      _sumDeleted(modifiedTools) +
      _sumDeleted(modifiedOther) +
      _sumDeleted(actionableDeleted);

  Map<String, dynamic> toJson() => {
        'merge_base': mergeBase,
        'head': head,
        'counts': {
          'total_added_files': totalAddedFiles,
          'total_modified_files': totalModifiedFiles,
          'total_deleted_files': totalDeletedFiles,
          'safe_deleted_files': safeDeleted.length,
          'actionable_deleted_files': actionableDeleted.length,
          'total_insertions': totalInsertions,
          'total_deletions': totalDeletions,
        },
        'added': {
          'bazel_infra': bazelInfra.map((e) => e.toJson()).toList(),
          'agent_meta': agentMeta.map((e) => e.toJson()).toList(),
          'other': addedOther.map((e) => e.toJson()).toList(),
        },
        'modified': {
          'cpp_gn': modifiedCppGn.map((e) => e.toJson()).toList(),
          'dart': modifiedDart.map((e) => e.toJson()).toList(),
          'tools': modifiedTools.map((e) => e.toJson()).toList(),
          'other': modifiedOther.map((e) => e.toJson()).toList(),
        },
        'deleted': {
          'safe': safeDeleted.map((e) => e.toJson()).toList(),
          'actionable': actionableDeleted.map((e) => e.toJson()).toList(),
        },
      };
}

bool _isBazelInfra(String path) {
  final file = path.split('/').last;
  return file == 'BUILD.bazel' ||
      file == 'WORKSPACE' ||
      file == 'MODULE.bazel' ||
      file == '.bazelignore' ||
      file == '.bazelversion' ||
      file == '.bazelrc' ||
      path.endsWith('.bzl') ||
      path.startsWith('tools/bazel/');
}

bool _isAgentMeta(String path) {
  return path.startsWith('.agents/') ||
      path.startsWith('.beads/') ||
      path.startsWith('.codex/') ||
      path.startsWith('.claude/') ||
      path.startsWith('docs/bazel-migration/') ||
      path.startsWith('todo_issues/');
}

bool _isSafeDeleted(String path) {
  return path.startsWith('.github/');
}

bool _isCppOrGn(String path) {
  return path.startsWith('runtime/') ||
      path.startsWith('third_party/') ||
      path.endsWith('.gn') ||
      path.endsWith('.gni') ||
      path.endsWith('.cc') ||
      path.endsWith('.h');
}

bool _isDartCode(String path) {
  return path.startsWith('pkg/') ||
      path.startsWith('tests/') ||
      path.startsWith('utils/') ||
      path.endsWith('.dart');
}

bool _isToolScript(String path) {
  return path.startsWith('tools/') || path == 'PRESUBMIT.py';
}

void _printHumanSummary(Delta delta, String upstreamRef) {
  print(
      '================================================================================');
  print(
      '               BAZEL FORK DELTA vs UPSTREAM ($upstreamRef)                      ');
  print(
      '================================================================================');
  print(' Merge Base : ${delta.mergeBase}');
  print(
      ' Total Files: ${delta.totalAddedFiles} Added (${delta.bazelInfra.length + delta.agentMeta.length} safe infra/meta, ${delta.addedOther.length} other) | '
      '${delta.totalModifiedFiles} Modified | '
      '${delta.totalDeletedFiles} Deleted (${delta.safeDeleted.length} safe masked CI, ${delta.actionableDeleted.length} actionable)');
  print(
      ' Total Lines: +${delta.totalInsertions} insertions, -${delta.totalDeletions} deletions');
  print(
      '================================================================================');

  _printSection(
      'MODIFIED UPSTREAM FILES (Crucial for SDK Maintenance & Roll Drift)', [
    SectionBag('C++ Runtime & GN Files', delta.modifiedCppGn),
    SectionBag('Dart Packages & Tests', delta.modifiedDart),
    SectionBag('Build & Tooling Scripts', delta.modifiedTools),
    SectionBag('Other Upstream Files', delta.modifiedOther),
  ]);

  _printSection('ACTIONABLE DELETED UPSTREAM FILES (Requires Review)', [
    SectionBag('Actionable Deleted Files', delta.actionableDeleted),
  ]);

  _printSection(
      'SAFE DELETED UPSTREAM FILES (By Design - Masked Upstream CI / Workflows)',
      [
        SectionBag('Safe Deletes (.github/)', delta.safeDeleted),
      ]);

  _printSection('ADDED BAZEL & AGENT INFRASTRUCTURE (Safe Fork-Only Files)', [
    SectionBag('Other Added Files (Requires Review)', delta.addedOther),
    SectionBag('Bazel Build Infrastructure', delta.bazelInfra),
    SectionBag('AI Agent Skills, Backlog & Memory', delta.agentMeta),
  ]);

  print(
      '================================================================================');
  print('  💡 Tip: To inspect the exact diff for any group or file, run:');
  print('     dart tools/bazel/fork_delta.dart --diff <category_or_file_path>');
  print(
      '================================================================================');
}

class SectionBag {
  final String title;
  final List<FileStat> files;
  SectionBag(this.title, this.files);
}

void _printSection(String mainTitle, List<SectionBag> bags) {
  if (bags.every((b) => b.files.isEmpty)) return;

  print('\n🔷 $mainTitle');
  for (final bag in bags) {
    if (bag.files.isEmpty) continue;
    final bagInsertions = bag.files.fold(0, (sum, item) => sum + item.added);
    final bagDeletions = bag.files.fold(0, (sum, item) => sum + item.deleted);
    print(
        '\n   🔸 ${bag.title} (${bag.files.length} files, +$bagInsertions, -$bagDeletions lines):');
    for (final f in bag.files) {
      print('      - $f');
    }
  }
}

void _printUpstreamCl(Delta delta, String upstreamRef) {
  print(
      '================================================================================');
  print(
      '          UPSTREAM CL CANDIDATE FILES vs UPSTREAM ($upstreamRef)                ');
  print(
      '================================================================================');
  print(' Merge Base : ${delta.mergeBase}');
  print(' Total Files: ${delta.totalModifiedFiles} Modified | '
      '${delta.actionableDeleted.length} Actionable Deleted (${delta.safeDeleted.length} safe .github/ deletes filtered out)');
  print(
      ' Total Lines: +${delta.upstreamModifiedInsertions} insertions, -${delta.upstreamModifiedDeletions} deletions across candidate files');
  print(
      ' (Completely filters out all Bazel build files, AI Agent tracking, and safe .github deletions)');
  print(
      '================================================================================');

  _printSection('MODIFIED UPSTREAM FILES (Candidates to Send Upstream)', [
    SectionBag('C++ Runtime & GN Files', delta.modifiedCppGn),
    SectionBag('Dart Packages & Tests', delta.modifiedDart),
    SectionBag('Build & Tooling Scripts', delta.modifiedTools),
    SectionBag('Other Upstream Files', delta.modifiedOther),
  ]);

  _printSection('ACTIONABLE DELETED UPSTREAM FILES (Requires Review)', [
    SectionBag('Actionable Deleted Files', delta.actionableDeleted),
  ]);
  print(
      '================================================================================');
}

Future<int?> _printDiff(
    String target, Delta delta, String mergeBase, bool isJson) {
  List<String> filesToDiff = [];
  switch (target) {
    case 'bazel-infra':
      filesToDiff = delta.bazelInfra.map((e) => e.path).toList();
      break;
    case 'agent-meta':
      filesToDiff = delta.agentMeta.map((e) => e.path).toList();
      break;
    case 'added-other':
      filesToDiff = delta.addedOther.map((e) => e.path).toList();
      break;
    case 'modified-cpp-gn':
      filesToDiff = delta.modifiedCppGn.map((e) => e.path).toList();
      break;
    case 'modified-dart':
      filesToDiff = delta.modifiedDart.map((e) => e.path).toList();
      break;
    case 'modified-tools':
      filesToDiff = delta.modifiedTools.map((e) => e.path).toList();
      break;
    case 'modified-other':
      filesToDiff = delta.modifiedOther.map((e) => e.path).toList();
      break;
    case 'deleted':
      filesToDiff = [
        ...delta.safeDeleted.map((e) => e.path),
        ...delta.actionableDeleted.map((e) => e.path)
      ];
      break;
    default:
      filesToDiff = [target]; // Assume exact file path
  }

  if (filesToDiff.isEmpty) {
    if (isJson) {
      print(jsonEncode({'error': 'No files found for diff target: $target'}));
    } else {
      print('No files match diff target: $target');
    }
    return Future.value(null);
  }

  return Process.start('git', ['diff', mergeBase, 'HEAD', '--', ...filesToDiff])
      .then((process) async {
    await Future.wait([
      stdout.addStream(process.stdout).catchError((_) {}),
      stderr.addStream(process.stderr).catchError((_) {}),
    ]);
    return process.exitCode;
  });
}

void _error(String msg, bool isJson) {
  if (isJson) {
    print(jsonEncode({'error': msg}));
  } else {
    stderr.writeln(msg);
  }
}
