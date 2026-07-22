// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";
import "dart:convert";
import "dart:io";

import "package:expect/async_helper.dart";
import "package:expect/expect.dart";

Future<void> testGZipFlushThenWrite() async {
  asyncStart();
  final server = await HttpServer.bind("127.0.0.1", 0);
  server.autoCompress = true;
  server.listen((request) async {
    final response = request.response;
    response.headers.chunkedTransferEncoding = true;
    response.write("part1_data_");
    await response.flush();
    response.write("part2_data");
    await response.close();
  });

  final client = HttpClient();
  final request = await client.get("127.0.0.1", server.port, "/");
  request.headers.set(HttpHeaders.acceptEncodingHeader, "gzip");
  final response = await request.close();
  Expect.equals(
    "gzip",
    response.headers.value(HttpHeaders.contentEncodingHeader),
  );
  final body = await response.transform(utf8.decoder).join();
  Expect.equals("part1_data_part2_data", body);

  client.close();
  await server.close();
  asyncEnd();
}

Future<void> testClientAbortMicrotaskZoneSafety() async {
  asyncStart();
  final errors = <dynamic>[];
  final server = await ServerSocket.bind("127.0.0.1", 0);
  server.listen((socket) => socket.destroy());

  await runZonedGuarded(
    () async {
      final client = HttpClient();
      final request = await client.post("127.0.0.1", server.port, "/");
      request.contentLength = 10;
      request.abort();
      await Future.delayed(const Duration(milliseconds: 50));
      client.close(force: true);
    },
    (error, stack) {
      errors.add(error);
    },
  );

  Expect.isTrue(
    errors.isEmpty,
    "No unhandled asynchronous exception should escape to zone on abort(): $errors",
  );
  await server.close();
  asyncEnd();
}

Future<void> testClientCloseNoDeadlockOnStreamError() async {
  asyncStart();
  final server = await ServerSocket.bind("127.0.0.1", 0);
  server.listen((socket) {
    socket.listen((_) => socket.destroy());
  });

  final client = HttpClient();
  final request = await client.post("127.0.0.1", server.port, "/");
  final controller = StreamController<List<int>>();
  final addStreamFuture = request.addStream(controller.stream);
  controller.add(List.filled(1024, 65));
  await controller.close();

  try {
    await addStreamFuture;
  } catch (_) {}

  try {
    await request.close();
  } catch (_) {}

  client.close(force: true);
  await server.close();
  asyncEnd();
}

Future<void> testUnawaitedFlushThenWrite() async {
  asyncStart();
  final server = await HttpServer.bind("127.0.0.1", 0);
  server.listen((request) async {
    final response = request.response;
    response.write("chunk1_");
    await response.flush();
    unawaited(response.flush());
    response.write("chunk2");
    await response.close();
  });

  final client = HttpClient();
  final response = await (await client.get(
    "127.0.0.1",
    server.port,
    "/",
  )).close();
  final body = await response.transform(utf8.decoder).join();
  Expect.equals("chunk1_chunk2", body);

  client.close();
  await server.close();
  asyncEnd();
}

void main() async {
  asyncStart();
  await testGZipFlushThenWrite();
  await testClientAbortMicrotaskZoneSafety();
  await testClientCloseNoDeadlockOnStreamError();
  await testUnawaitedFlushThenWrite();
  asyncEnd();
}
