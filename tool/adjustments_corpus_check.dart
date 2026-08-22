/// Audits adjustment decoding and lossless re-encoding in a PSD corpus.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';

/// Scans the directory passed on the command line and prints adjustment statistics.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/adjustments_corpus_check.dart <directory>');
    exitCode = 64;
    return;
  }
  final Directory root = Directory(arguments.single);
  if (!root.existsSync()) {
    stderr.writeln('Directory not found: ${root.path}');
    exitCode = 66;
    return;
  }

  int documents = 0;
  int documentFailures = 0;
  int blocks = 0;
  int decodedBlocks = 0;
  int semanticBlocks = 0;
  int stableBlocks = 0;
  final Map<String, int> keys = <String, int>{};
  await for (final FileSystemEntity entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File || !_isPhotoshopPath(entity.path)) {
      continue;
    }
    documents++;
    try {
      final PsdDocument document = PsdCodec.decode(await entity.readAsBytes());
      for (final PsdLayer layer in document.layers) {
        for (final PsdTaggedBlock block in layer.additionalInfo) {
          if (!psdAdjustmentKeys.contains(block.key)) {
            continue;
          }
          blocks++;
          keys.update(block.key, (count) => count + 1, ifAbsent: () => 1);
          final PsdAdjustment? adjustment = PsdAdjustmentCodec.tryDecode(block.data, key: block.key);
          if (adjustment == null) {
            stdout.writeln('ADJUSTMENT ERROR\t${entity.path}\t${layer.name}\t${block.key}');
            continue;
          }
          decodedBlocks++;
          if (adjustment is! PsdRawAdjustment) {
            semanticBlocks++;
          }
          if (_equalBytes(block.data, PsdAdjustmentCodec.encode(adjustment))) {
            stableBlocks++;
          } else {
            stdout.writeln('ADJUSTMENT CHANGED\t${entity.path}\t${layer.name}\t${block.key}');
          }
        }
      }
    } on Object catch (error) {
      documentFailures++;
      stdout.writeln('PSD ERROR\t${entity.path}\t$error');
    }
  }
  final List<String> sortedKeys = keys.keys.toList()..sort();
  stdout.writeln(
    'documents=$documents documentFailures=$documentFailures blocks=$blocks '
    'decoded=$decodedBlocks semantic=$semanticBlocks raw=${decodedBlocks - semanticBlocks} '
    'byteStable=$stableBlocks keys=${<String>[for (final String key in sortedKeys) '$key:${keys[key]}'].join(',')}',
  );
  if (documentFailures != 0 || decodedBlocks != blocks || stableBlocks != decodedBlocks) {
    exitCode = 1;
  }
}

/// Whether [path] has a PSD or PSB extension.
bool _isPhotoshopPath(String path) {
  final String lower = path.toLowerCase();
  return lower.endsWith('.psd') || lower.endsWith('.psb');
}

/// Whether [first] and [second] contain identical bytes.
bool _equalBytes(Uint8List first, Uint8List second) {
  if (first.length != second.length) {
    return false;
  }
  for (int index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}
