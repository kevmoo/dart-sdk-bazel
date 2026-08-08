import 'dart:typed_data';

void main() {
  final int count = 10000000;
  final str = "  -3.1415926535  ";
  final bytes = Uint8List.fromList(str.codeUnits);

  final intStr = "  -9876543210  ";
  final intBytes = Uint8List.fromList(intStr.codeUnits);

  print("Warming up...");
  for (int i = 0; i < 100000; i++) {
    double.parse(str);
    double.parseUtf8(bytes);
    int.parse(intStr);
    int.parseUtf8(intBytes);
  }

  print("Measuring double.parse(String)...");
  final sw1 = Stopwatch()..start();
  for (int i = 0; i < count; i++) {
    double.parse(str);
  }
  sw1.stop();
  final dParseMs = sw1.elapsedMilliseconds;
  print("double.parse: ${dParseMs} ms");

  print("Measuring double.parseUtf8(Uint8List)...");
  final sw2 = Stopwatch()..start();
  for (int i = 0; i < count; i++) {
    double.parseUtf8(bytes);
  }
  sw2.stop();
  final dUtf8Ms = sw2.elapsedMilliseconds;
  print("double.parseUtf8: ${dUtf8Ms} ms");

  print("Measuring int.parse(String)...");
  final sw3 = Stopwatch()..start();
  for (int i = 0; i < count; i++) {
    int.parse(intStr);
  }
  sw3.stop();
  final iParseMs = sw3.elapsedMilliseconds;
  print("int.parse: ${iParseMs} ms");

  print("Measuring int.parseUtf8(Uint8List)...");
  final sw4 = Stopwatch()..start();
  for (int i = 0; i < count; i++) {
    int.parseUtf8(intBytes);
  }
  sw4.stop();
  final iUtf8Ms = sw4.elapsedMilliseconds;
  print("int.parseUtf8: ${iUtf8Ms} ms");
}
