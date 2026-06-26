// Generates BACKLOG.md + BACKLOG_HISTORY.md from the beads issue DB (canonical).
//
// Beads (`bd`) is the source of truth for Bazel-migration tasks. This regenerates
// the human-readable board + mermaid dependency graph from `bd export`. Run it
// after changing tasks in beads (from the repo root):
//
//     tools/sdks/dart-sdk/bin/dart docs/bazel-migration/gen_board_from_beads.dart
//     bd dolt push        # ship the beads change to the fork (refs/dolt/data)

import 'dart:convert';
import 'dart:io';

const Map<String, String> kStatus = {
  'closed': 'COMPLETED',
  'blocked': 'BLOCKED',
  'in_progress': 'IN_PROGRESS',
  'open': 'PENDING',
};
const Map<String, String> kMermaidClass = {
  'COMPLETED': 'completed',
  'IN_PROGRESS': 'inProgress',
  'BLOCKED': 'blocked',
  'PENDING': 'pending',
};

class SuccessCriterion {
  final String description;
  final bool verified;
  SuccessCriterion(this.description, this.verified);
}

class Task {
  final String id;
  final String title;
  final String status;
  final List<String> prerequisites;
  final List<String> labels;
  final String owner;
  final String commit;
  final List<String> targetFiles;
  final String verificationCommand;
  final List<SuccessCriterion> successCriteria;
  final String description;
  final String externalRef;

  Task({
    required this.id,
    required this.title,
    required this.status,
    required this.prerequisites,
    required this.labels,
    required this.owner,
    required this.commit,
    required this.targetFiles,
    required this.verificationCommand,
    required this.successCriteria,
    required this.description,
    required this.externalRef,
  });

  bool isLater(Map<String, Map<String, dynamic>> tagDefs) {
    for (final label in labels) {
      final def = tagDefs[label];
      if (def != null && def['later'] == true) {
        return true;
      }
    }
    return false;
  }
}

void main() {
  final Directory scriptDir = File(Platform.script.toFilePath()).parent;
  final File tagDefsFile = File('${scriptDir.path}/beads/tag_definitions.json');

  Map<String, Map<String, dynamic>> tagDefs = {};
  if (tagDefsFile.existsSync()) {
    try {
      final String content = tagDefsFile.readAsStringSync();
      final Map raw = jsonDecode(content) as Map;
      tagDefs = raw.map(
        (k, v) => MapEntry(k.toString(), (v as Map).cast<String, dynamic>()),
      );

      // Sync to beads memory
      Process.runSync('bd', [
        'remember',
        'tag-definitions',
        content.replaceAll('\n', ' '),
      ]);
    } catch (e) {
      stderr.writeln('Warning: Failed to load tag_definitions.json: $e');
    }
  }

  final ProcessResult res = Process.runSync('bd', ['export']);
  if (res.exitCode != 0) {
    stderr.writeln('Error: `bd export` failed: ${res.stderr}');
    exit(1);
  }

  final Map<String, Map<String, dynamic>> byBead = {};
  final List<Map<String, dynamic>> records = [];
  for (final String line in (res.stdout as String).split('\n')) {
    if (line.trim().isEmpty) continue;
    final Map<String, dynamic> r = jsonDecode(line) as Map<String, dynamic>;
    dynamic md = r['metadata'];
    if (md is String) md = md.isEmpty ? {} : jsonDecode(md);
    r['_md'] = (md as Map?) ?? {};
    byBead[r['id'] as String] = r;
    records.add(r);
  }

  String dispId(Map<String, dynamic> r) => r['id'] as String;
  String orNone(dynamic v) => (v is String && v.isNotEmpty) ? v : 'none';

  final List<Task> tasks = [];
  for (final r in records) {
    final Map md = r['_md'] as Map;
    final List deps = (r['dependencies'] as List?) ?? [];
    final List<String> prereqs =
        deps
            .map((d) => d['depends_on_id'])
            .where((id) => byBead.containsKey(id))
            .map((id) => dispId(byBead[id]!))
            .toList()
          ..sort();
    final List criteria =
        jsonDecode(md['success_criteria'] as String? ?? '[]') as List;
    final List<String> labels = (r['labels'] as List? ?? []).cast<String>();

    tasks.add(
      Task(
        id: dispId(r),
        title: r['title'] as String,
        status: kStatus[r['status']] ?? 'PENDING',
        prerequisites: prereqs,
        labels: labels,
        owner: orNone(md['owner']),
        commit: orNone(md['commit']),
        targetFiles: (jsonDecode(md['target_files'] as String? ?? '[]') as List)
            .cast<String>(),
        verificationCommand: md['verification_command'] as String? ?? '',
        successCriteria: criteria
            .map(
              (c) => SuccessCriterion(
                c['description'] as String,
                c['verified'] == true,
              ),
            )
            .toList(),
        description:
            md['description_raw'] as String? ??
            r['description'] as String? ??
            '',
        externalRef: r['external_ref'] as String? ?? '',
      ),
    );
  }

  tasks.sort((a, b) => a.id.compareTo(b.id));

  File(
    '${scriptDir.path}/BACKLOG.md',
  ).writeAsStringSync(generateBacklog(tasks, tagDefs));
  File(
    '${scriptDir.path}/BACKLOG_HISTORY.md',
  ).writeAsStringSync(generateHistory(tasks));

  final int done = tasks.where((t) => t.status == 'COMPLETED').length;
  print(
    'Wrote BACKLOG.md + BACKLOG_HISTORY.md from beads '
    '(${tasks.length} tasks, $done completed, ${tasks.length - done} active)',
  );
}

String generateMermaid(List<Task> tasks) {
  final StringBuffer sb = StringBuffer();
  sb.writeln('```mermaid');
  sb.writeln('graph TD');
  sb.writeln(
    '    classDef completed fill:#d4edda,stroke:#28a745,stroke-width:2px,color:#155724;',
  );
  sb.writeln(
    '    classDef inProgress fill:#fff3cd,stroke:#ffc107,stroke-width:2px,color:#856404;',
  );
  sb.writeln(
    '    classDef pending fill:#f8f9fa,stroke:#6c757d,stroke-width:1px,stroke-dasharray: 5 5,color:#6c757d;',
  );
  sb.writeln(
    '    classDef blocked fill:#f8d7da,stroke:#dc3545,stroke-width:1px,stroke-dasharray: 5 5,color:#721c24;',
  );

  for (final Task task in tasks) {
    final String cleanTitle = task.title
        .replaceAll('"', '\\"')
        .replaceAll('[', '{')
        .replaceAll(']', '}')
        .replaceAll('(', '{')
        .replaceAll(')', '}');
    final String node = task.id.replaceAll('-', '_');
    sb.writeln(
      '    $node["${task.id}:<br>$cleanTitle"]:::${kMermaidClass[task.status]}',
    );
  }

  sb.writeln();
  for (final Task task in tasks) {
    for (final String prereq in task.prerequisites) {
      sb.writeln(
        '    ${prereq.replaceAll('-', '_')} --> ${task.id.replaceAll('-', '_')}',
      );
    }
  }
  sb.writeln('```');
  return sb.toString();
}

String generateBacklog(
  List<Task> tasks,
  Map<String, Map<String, dynamic>> tagDefs,
) {
  final int done = tasks.where((t) => t.status == 'COMPLETED').length;
  final List<Task> uncompleted = tasks
      .where((t) => t.status != 'COMPLETED')
      .toList();

  final List<Task> active = uncompleted
      .where((t) => !t.isLater(tagDefs))
      .toList();
  final List<Task> later = uncompleted
      .where((t) => t.isLater(tagDefs))
      .toList();

  final StringBuffer sb = StringBuffer();
  sb.writeln('# Dart SDK Bazel Migration: Active Backlog & Coordination Board');
  sb.writeln();
  sb.writeln(
    'This board is generated from the **beads** issue DB (`bd`), which '
    'is the source of truth. **Do not edit this file directly.** To change '
    'tasks, use `bd` and then:',
  );
  sb.writeln(
    '`tools/sdks/dart-sdk/bin/dart docs/bazel-migration/gen_board_from_beads.dart && bd dolt push`',
  );
  sb.writeln();
  sb.writeln(
    'New machine, or `bd` not set up? See [BEADS.md](BEADS.md) for install + bootstrap.',
  );
  sb.writeln();
  sb.writeln('> 🚨 **AGENT PROTOCOL (Mandatory)**:');
  sb.writeln(
    '> 1. **Scan**: `bd ready` for actionable tasks; `bd blocked` for what is waiting.',
  );
  sb.writeln(
    '> 2. **Claim**: `bd update <id> --status in_progress --assignee <you>`.',
  );
  sb.writeln('> 3. **Verify**: run the task\'s Verification Command.');
  sb.writeln(
    '> 4. **Update**: `bd close <id>` when green, then regenerate this board and `bd dolt push`.',
  );
  sb.writeln();
  sb.writeln('---');
  sb.writeln();
  sb.writeln('## 📊 Global State');
  sb.writeln();
  sb.writeln('- **Active Agent**: `[none]`');
  sb.writeln('- **Global Lock**: `[unlocked]`');
  sb.writeln(
    '- **Overall Progress**: $done/${tasks.length} Tasks (Completed details in [BACKLOG_HISTORY.md](BACKLOG_HISTORY.md))',
  );
  sb.writeln();

  if (tagDefs.isNotEmpty) {
    sb.writeln('### 🏷️ Tag Distribution Metrics');
    sb.writeln();
    sb.writeln('| Tag | Scope / Description | Active | Deferred (Later) |');
    sb.writeln('| :--- | :--- | :---: | :---: |');
    final RegExp validTagRegex = RegExp(r'^[a-z0-9-]+$');
    for (final entry in tagDefs.entries) {
      final tag = entry.key;
      final desc = entry.value['description'] ?? '';
      final activeCount = active.where((t) => t.labels.contains(tag)).length;
      final laterCount = later.where((t) => t.labels.contains(tag)).length;
      final tagLabel = validTagRegex.hasMatch(tag)
          ? '`$tag`'
          : '`$tag` 🚨 INVALID TAG FORMAT';
      sb.writeln('| $tagLabel | $desc | $activeCount | $laterCount |');
    }
    sb.writeln();
  }

  sb.writeln('---');
  sb.writeln();
  sb.writeln('## 🗺️ Dependency Graph');
  sb.writeln();
  sb.writeln('<!-- START_DEP_GRAPH -->');
  sb.writeln(generateMermaid(tasks));
  sb.writeln('<!-- END_DEP_GRAPH -->');
  sb.writeln();
  sb.writeln('---');
  sb.writeln();
  sb.writeln('## 📋 Active Backlog');
  sb.writeln();
  if (active.isEmpty) {
    sb.writeln('🎉 **No active tasks pending!**');
  } else {
    for (final Task task in active) {
      sb.writeln(generateTaskMarkdown(task));
      sb.writeln('---');
      sb.writeln();
    }
  }

  if (later.isNotEmpty) {
    sb.writeln();
    sb.writeln('---');
    sb.writeln();
    sb.writeln('## ⏳ Deferred Backlog (`later`)');
    sb.writeln();
    for (final Task task in later) {
      sb.writeln(generateTaskMarkdown(task));
      sb.writeln('---');
      sb.writeln();
    }
  }

  return sb.toString();
}

String generateHistory(List<Task> tasks) {
  final List<Task> completed = tasks
      .where((t) => t.status == 'COMPLETED')
      .toList();
  final StringBuffer sb = StringBuffer();
  sb.writeln('# Dart SDK Bazel Migration: Completed Tasks History');
  sb.writeln();
  sb.writeln(
    'This file lists all completed tasks in the Bazel migration. It is '
    'generated from the beads issue DB by '
    '`docs/bazel-migration/gen_board_from_beads.dart`.',
  );
  sb.writeln();
  sb.writeln('---');
  sb.writeln();
  sb.writeln('## 📜 Completed Tasks');
  sb.writeln();
  if (completed.isEmpty) {
    sb.writeln('No tasks completed yet.');
  } else {
    for (final Task task in completed) {
      sb.writeln(generateTaskMarkdown(task));
      sb.writeln('---');
      sb.writeln();
    }
  }
  return sb.toString();
}

String formatExternalRef(String ref) {
  final uri = Uri.tryParse(ref);
  if (uri != null && uri.host == 'github.com') {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length >= 4 && segments[segments.length - 2] == 'pull') {
      return 'PR #${segments.last}';
    }
  }
  return 'Link';
}

String generateTaskMarkdown(Task task) {
  final StringBuffer sb = StringBuffer();
  sb.writeln('### 🎯 [${task.id}] ${task.title}');
  sb.writeln('- **Status**: `[${task.status}]`');
  if (task.labels.isNotEmpty) {
    sb.writeln('- **Tags**: ${task.labels.map((l) => '`$l`').join(', ')}');
  }
  if (task.externalRef.isNotEmpty) {
    final label = formatExternalRef(task.externalRef);
    sb.writeln('- **PR/External Ref**: [$label](${task.externalRef})');
  }
  final String prereqs = task.prerequisites.isEmpty
      ? 'None'
      : task.prerequisites.map((p) => '`$p`').join(', ');
  sb.writeln('- **Prerequisites**: $prereqs');
  sb.writeln('- **Owner**: `[${task.owner}]`');
  sb.writeln('- **Commit**: `[${task.commit}]`');
  sb.writeln('- **Target Files**:');
  if (task.targetFiles.isEmpty) {
    sb.writeln('  - None');
  } else {
    for (final String file in task.targetFiles) {
      sb.writeln('  - `$file`');
    }
  }
  sb.writeln('- **Description**:');
  sb.writeln(task.description.split('\n').map((l) => '  $l').join('\n'));
  if (task.verificationCommand.trim().isNotEmpty) {
    sb.writeln('- **Verification Command**:');
    sb.writeln('  ```bash');
    sb.writeln(
      task.verificationCommand.split('\n').map((l) => '  $l').join('\n'),
    );
    sb.writeln('  ```');
  }
  sb.writeln('- **Success Criteria**:');
  for (final SuccessCriterion c in task.successCriteria) {
    sb.writeln('  - ${c.verified ? '[x]' : '[ ]'} ${c.description}');
  }
  return sb.toString();
}
