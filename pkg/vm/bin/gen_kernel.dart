// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io' as io;

import 'dart:convert';
import 'package:args/args.dart' show ArgParser;
import 'package:kernel/text/ast_to_text.dart'
    show globalDebuggingNames, NameSystem;
import 'package:kernel/src/tool/batch_util.dart' as batch_util;
import 'package:vm/kernel_front_end.dart'
    show
        createCompilerArgParser,
        runCompiler,
        successExitCode,
        compileTimeErrorExitCode,
        badUsageExitCode;

final ArgParser _argParser = createCompilerArgParser();

final String _usage =
    '''
Usage: dart pkg/vm/bin/gen_kernel.dart --platform vm_platform.dill [options] input.dart
Compiles Dart sources to a kernel binary file for Dart VM.

Options:
${_argParser.usage}
''';

void main(List<String> arguments) async {
  if (arguments.isNotEmpty && arguments.last == '--batch') {
    await runBatchModeCompiler();
  } else if (arguments.isNotEmpty &&
      arguments.contains('--persistent_worker')) {
    await runPersistentWorker();
  } else {
    io.exitCode = await compile(arguments);
  }
}

Future<int> compile(List<String> arguments) async {
  final expandedArgs = <String>[];
  for (final arg in arguments) {
    if (arg.startsWith('@')) {
      final paramFile = io.File(arg.substring(1));
      if (paramFile.existsSync()) {
        expandedArgs.addAll(
          paramFile
              .readAsLinesSync()
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty),
        );
      } else {
        expandedArgs.add(arg);
      }
    } else {
      expandedArgs.add(arg);
    }
  }
  return runCompiler(_argParser.parse(expandedArgs), _usage);
}

Future runPersistentWorker() async {
  final lines = io.stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  await for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    Map<String, dynamic> request;
    try {
      request = jsonDecode(trimmed) as Map<String, dynamic>;
    } catch (e) {
      continue;
    }

    final requestId = request['requestId'] ?? request['id'] ?? 0;
    final rawArgs =
        (request['arguments'] as List?)?.cast<String>() ?? <String>[];

    final outputBuffer = StringBuffer();
    int exitCode = 0;

    await runZoned(
      () async {
        try {
          exitCode = await compile(rawArgs);
        } catch (e, st) {
          exitCode = 1;
          outputBuffer.writeln('Worker compilation error: $e\n$st');
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, message) {
          outputBuffer.writeln(message);
        },
      ),
    );

    // Re-create global NameSystem to avoid accumulating garbage.
    globalDebuggingNames = NameSystem();

    final response = <String, dynamic>{
      'exitCode': exitCode,
      'output': outputBuffer.toString(),
      'requestId': requestId,
    };

    io.stdout.writeln(jsonEncode(response));
  }
}

Future runBatchModeCompiler() async {
  await batch_util.runBatch((List<String> arguments) async {
    // TODO(kustermann): Once we know where the new IKG api is and how to use
    // it, we should take advantage of it.
    //
    // Important things to note:
    //
    //   * Our global transformations must never alter the AST structures which
    //     the stateful IKG generator keeps across compilations.
    //     => We need to make our own copy.
    //
    //   * We must ensure the stateful IKG generator keeps giving us all the
    //     compile-time errors, warnings, hints for every compilation and we
    //     report the compilation result accordingly.
    //
    final exitCode = await compile(arguments);

    // Re-create global NameSystem to avoid accumulating garbage.
    globalDebuggingNames = new NameSystem();

    switch (exitCode) {
      case successExitCode:
        return batch_util.CompilerOutcome.Ok;
      case compileTimeErrorExitCode:
      case badUsageExitCode:
        return batch_util.CompilerOutcome.Fail;
      default:
        throw 'Could not obtain correct exit code from compiler.';
    }
  });
}
