// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "package:expect/expect.dart";

import "dart:typed_data";

void testIntUtf8(String str, int? expected, {int? radix}) {
  final bytes = Uint8List.fromList(str.codeUnits);

  if (expected != null) {
    Expect.equals(expected, int.parseUtf8(bytes, radix: radix));
    Expect.equals(expected, int.tryParseUtf8(bytes, radix: radix));
  } else {
    Expect.throwsFormatException(() => int.parseUtf8(bytes, radix: radix));
    Expect.isNull(int.tryParseUtf8(bytes, radix: radix));
  }
}

void testIntUtf8Range(String str, int? expected, int start, [int? end]) {
  final bytes = Uint8List.fromList(str.codeUnits);

  if (expected != null) {
    Expect.equals(expected, int.parseUtf8(bytes, start: start, end: end));
    Expect.equals(expected, int.tryParseUtf8(bytes, start: start, end: end));
  } else {
    Expect.throwsFormatException(
      () => int.parseUtf8(bytes, start: start, end: end),
    );
    Expect.isNull(int.tryParseUtf8(bytes, start: start, end: end));
  }
}

void main() {
  testIntUtf8("0", 0);
  testIntUtf8("1", 1);
  testIntUtf8("-1", -1);
  testIntUtf8("9876543210", 9876543210);
  testIntUtf8("-9876543210", -9876543210);

  // Whitespace skipping
  testIntUtf8("  42  ", 42);
  testIntUtf8("\t 42 \n\r", 42);

  // Hex
  testIntUtf8("0x10", 16);
  testIntUtf8("-0x10", -16);
  testIntUtf8("0XF", 15);

  // Custom radix
  testIntUtf8("10", 2, radix: 2);
  testIntUtf8("FF", 255, radix: 16);
  testIntUtf8("z", 35, radix: 36);

  // Int overflow cases handling
  testIntUtf8("9223372036854775807", 9223372036854775807);
  testIntUtf8("-9223372036854775808", -9223372036854775808);

  // Ranges
  testIntUtf8Range("a123b", 123, 1, 4);
  testIntUtf8Range("a 12 b", 12, 1, 5);

  // Invalid
  testIntUtf8("", null);
  testIntUtf8("  ", null);
  testIntUtf8("1.2", null);
  testIntUtf8("abc", null);
  testIntUtf8("--1", null);
  testIntUtf8("123a", null);
}
