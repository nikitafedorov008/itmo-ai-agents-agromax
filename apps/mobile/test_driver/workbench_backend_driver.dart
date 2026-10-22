import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      final directory = Directory('build/native-evidence');
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: (data) async {
      final proof = data?['workbenchProof'];
      if (proof != null) {
        final directory = Directory('build/native-evidence');
        await directory.create(recursive: true);
        await File(
          '${directory.path}/workbench-proof.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(proof));
      }
    },
  );
}
