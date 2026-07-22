// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";
import "dart:io";

import "package:expect/async_helper.dart";
import "package:expect/expect.dart";

Future<void> testConcurrentAddStream() async {
  asyncStart();
  final server = await HttpServer.bind("127.0.0.1", 0);
  server.listen((request) async {
    try {
      await request.drain();
      await request.response.close();
    } catch (_) {}
  });

  var client = new HttpClient();
  try {
    final request = await client.get("127.0.0.1", server.port, "/");
    var controller1 = StreamController<List<int>>();

    // Add the first stream.
    var future1 = request.addStream(controller1.stream);

    // Concurrently add the second stream.
    // This should throw a StateError because the first addStream is not complete.
    Expect.throwsStateError(() {
      request.addStream(Stream.empty());
    });

    // Clean up.
    await controller1.close();
    await future1;
    final response = await request.close();
    await response.drain();
  } catch (e) {
    Expect.fail("Unexpected error: $e");
  } finally {
    client.close();
    await server.close();
    asyncEnd();
  }
}

void main() async {
  await testConcurrentAddStream();
}
