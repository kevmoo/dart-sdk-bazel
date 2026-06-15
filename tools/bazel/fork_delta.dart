// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

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

void main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    print(usage);
    return;
  }

  final isJson = args.contains('--json');
  String upstreamRef = 'official/main';
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
  final gitDir = await _runGit(['rev-parse', '--git-dir']);
  if (gitDir == null) {
    _error('Fatal: Not inside a valid Git repository.', isJson);
    return;
  }

  // Find the merge base with upstream Ref
  final mergeBase = await _runGit(['merge-base', upstreamRef, 'HEAD']);
  if (mergeBase == null) {
    _error(
        'Fatal: Could not find merge base between $upstreamRef and HEAD. Make sure official remote is fetched.',
        isJson);
    return;
  }

  // Retrieve the full name-status delta
  final diffOutput =
      await _runGit(['diff', '--name-status', mergeBase, 'HEAD']);
  if (diffOutput == null) {
    _error('Fatal: Failed to run git diff against $mergeBase.', isJson);
    return;
  }

  final lines = diffOutput.trim().split('\n');
  final delta = Delta(mergeBase: mergeBase, head: 'HEAD');

  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final parts = line.split(RegExp(r'\s+'));
    final status = parts[0];
    final path = parts[1];

    if (status.startsWith('D')) {
      delta.deleted.add(path);
    } else if (status.startsWith('A')) {
      if (_isBazelInfra(path)) {
        delta.bazelInfra.add(path);
      } else if (_isAgentMeta(path)) {
        delta.agentMeta.add(path);
      } else {
        delta.addedOther.add(path);
      }
    } else if (status.startsWith('M')) {
      if (_isCppOrGn(path)) {
        delta.modifiedCppGn.add(path);
      } else if (_isDartCode(path)) {
        delta.modifiedDart.add(path);
      } else if (_isToolScript(path)) {
        delta.modifiedTools.add(path);
      } else {
        delta.modifiedOther.add(path);
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
            ...delta.modifiedCppGn,
            ...delta.modifiedDart,
            ...delta.modifiedTools,
            ...delta.modifiedOther
          ],
          'deleted': delta.deleted,
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

class Delta {
  final String mergeBase;
  final String head;

  final List<String> bazelInfra = [];
  final List<String> agentMeta = [];
  final List<String> addedOther = [];
  final List<String> modifiedCppGn = [];
  final List<String> modifiedDart = [];
  final List<String> modifiedTools = [];
  final List<String> modifiedOther = [];
  final List<String> deleted = [];

  Delta({required this.mergeBase, required this.head});

  Map<String, dynamic> toJson() => {
        'merge_base': mergeBase,
        'head': head,
        'counts': {
          'total_added':
              bazelInfra.length + agentMeta.length + addedOther.length,
          'total_modified': modifiedCppGn.length +
              modifiedDart.length +
              modifiedTools.length +
              modifiedOther.length,
          'total_deleted': deleted.length,
        },
        'added': {
          'bazel_infra': bazelInfra,
          'agent_meta': agentMeta,
          'other': addedOther,
        },
        'modified': {
          'cpp_gn': modifiedCppGn,
          'dart': modifiedDart,
          'tools': modifiedTools,
          'other': modifiedOther,
        },
        'deleted': deleted,
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
      ' Total Files: ${delta.bazelInfra.length + delta.agentMeta.length + delta.addedOther.length} Added | '
      '${delta.modifiedCppGn.length + delta.modifiedDart.length + delta.modifiedTools.length + delta.modifiedOther.length} Modified | '
      '${delta.deleted.length} Deleted');
  print(
      '================================================================================');

  _printSection(
      'MODIFIED UPSTREAM FILES (Crucial for SDK Maintenance & Roll Drift)', [
    SectionBag('C++ Runtime & GN Files', delta.modifiedCppGn),
    SectionBag('Dart Packages & Tests', delta.modifiedDart),
    SectionBag('Build & Tooling Scripts', delta.modifiedTools),
    SectionBag('Other Upstream Files', delta.modifiedOther),
  ]);

  _printSection('DELETED OR MASKED UPSTREAM FILES', [
    SectionBag('Deleted Files', delta.deleted),
  ]);

  _printSection('ADDED BAZEL & AGENT INFRASTRUCTURE (Fork-Only Files)', [
    SectionBag('Bazel Build Infrastructure', delta.bazelInfra),
    SectionBag('AI Agent Skills, Backlog & Memory', delta.agentMeta),
    SectionBag('Other Added Files', delta.addedOther),
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
  final List<String> files;
  SectionBag(this.title, this.files);
}

void _printSection(String mainTitle, List<SectionBag> bags) {
  if (bags.every((b) => b.files.isEmpty)) return;

  print('\n🔷 $mainTitle');
  for (final bag in bags) {
    if (bag.files.isEmpty) continue;
    print('\n   🔸 ${bag.title} (${bag.files.length}):');
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
  print(
      ' Total Files: ${delta.modifiedCppGn.length + delta.modifiedDart.length + delta.modifiedTools.length + delta.modifiedOther.length} Modified | '
      '${delta.deleted.length} Deleted');
  print(
      ' (Completely filters out all Bazel build files, AI Agent tracking, and helper additions)');
  print(
      '================================================================================');

  _printSection('MODIFIED UPSTREAM FILES (Candidates to Send Upstream)', [
    SectionBag('C++ Runtime & GN Files', delta.modifiedCppGn),
    SectionBag('Dart Packages & Tests', delta.modifiedDart),
    SectionBag('Build & Tooling Scripts', delta.modifiedTools),
    SectionBag('Other Upstream Files', delta.modifiedOther),
  ]);

  _printSection('DELETED OR MASKED UPSTREAM FILES', [
    SectionBag('Deleted Files', delta.deleted),
  ]);
  print(
      '================================================================================');
}

Future<int?> _printDiff(
    String target, Delta delta, String mergeBase, bool isJson) {
  List<String> filesToDiff = [];
  switch (target) {
    case 'bazel-infra':
      filesToDiff = delta.bazelInfra;
      break;
    case 'agent-meta':
      filesToDiff = delta.agentMeta;
      break;
    case 'added-other':
      filesToDiff = delta.addedOther;
      break;
    case 'modified-cpp-gn':
      filesToDiff = delta.modifiedCppGn;
      break;
    case 'modified-dart':
      filesToDiff = delta.modifiedDart;
      break;
    case 'modified-tools':
      filesToDiff = delta.modifiedTools;
      break;
    case 'modified-other':
      filesToDiff = delta.modifiedOther;
      break;
    case 'deleted':
      filesToDiff = delta.deleted;
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
      .then((process) {
    stdout.addStream(process.stdout);
    stderr.addStream(process.stderr);
    return process.exitCode;
  });
}

Future<String?> _runGit(List<String> args) async {
  try {
    final res = await Process.run('git', args);
    if (res.exitCode == 0) {
      return res.stdout.toString().trim();
    }
  } catch (_) {}
  return null;
}

void _error(String msg, bool isJson) {
  if (isJson) {
    print(jsonEncode({'error': msg}));
  } else {
    stderr.writeln(msg);
  }
}
