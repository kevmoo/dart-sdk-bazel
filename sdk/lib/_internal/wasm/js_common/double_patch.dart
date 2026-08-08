// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:typed_data' show Uint8List;
import "dart:_internal" show patch;
import 'dart:_js_helper' show JS;
import 'dart:_js_helper';

@patch
class double {
  @patch
  static double parseUtf8(Uint8List source, {int start = 0, int? end}) {
    double? value = tryParseUtf8(source, start: start, end: end);
    if (value != null) return value;
    throw FormatException("Invalid double");
  }

  @patch
  static double? tryParseUtf8(Uint8List source, {int start = 0, int? end}) {
    int actualEnd = end ?? source.length;
    if (start < 0 || start > actualEnd || actualEnd > source.length) {
      throw RangeError.range(start, 0, actualEnd);
    }
    if (start == actualEnd) return null;
    return tryParse(String.fromCharCodes(source, start, actualEnd));
  }

  @patch
  static double parse(String source) {
    double? result = tryParse(source);
    if (result == null) {
      throw FormatException('Invalid double $source');
    }
    return result;
  }

  @patch
  static double? tryParse(String source) {
    // Notice that JS parseFloat accepts garbage at the end of the string.
    // Accept only:
    // - [+/-]NaN
    // - [+/-]Infinity
    // - a Dart double literal
    // We do allow leading or trailing whitespace.
    double result = JS<double>(r"""s => {
      if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
        return NaN;
      }
      return parseFloat(s);
    }""", jsStringFromDartString(source).wrappedExternRef);
    if (result.isNaN) {
      String trimmed = source.trim();
      if (!(trimmed == 'NaN' || trimmed == '+NaN' || trimmed == '-NaN')) {
        return null;
      }
    }
    return result;
  }
}
