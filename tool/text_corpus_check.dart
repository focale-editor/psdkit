/// Audits text-layer decoding and lossless `TySh` re-encoding in a PSD corpus.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';

/// Scans the directory passed on the command line and prints text support statistics.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/text_corpus_check.dart <directory>');
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
  int textBlocks = 0;
  int decodedBlocks = 0;
  int stableBlocks = 0;
  int styledBlocks = 0;
  int editableBlocks = 0;
  await for (final FileSystemEntity entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File || !_isPhotoshopPath(entity.path)) {
      continue;
    }
    documents++;
    try {
      final PsdDocument document = PsdCodec.decode(await entity.readAsBytes());
      for (final PsdLayer layer in document.layers) {
        final PsdTaggedBlock? block = layer.taggedBlock('TySh');
        if (block == null) {
          continue;
        }
        textBlocks++;
        final PsdTypeTool? typeTool = PsdTypeToolCodec.tryDecode(block.data);
        if (typeTool == null) {
          stdout.writeln('TYSH ERROR\t${entity.path}\t${layer.name}');
          continue;
        }
        decodedBlocks++;
        if (_equalBytes(block.data, PsdTypeToolCodec.encode(typeTool))) {
          stableBlocks++;
        } else {
          final Uint8List encoded = PsdTypeToolCodec.encode(typeTool);
          final int difference = _firstDifference(block.data, encoded);
          stdout.writeln(
            'TYSH CHANGED\t${entity.path}\t${layer.name}\t'
            '${block.data.length}->${encoded.length}, first=$difference, '
            '${_hexWindow(block.data, difference)} -> ${_hexWindow(encoded, difference)}',
          );
        }
        if (typeTool.content.styleRuns.isNotEmpty) {
          styledBlocks++;
        }
        const String replacement =
            r'PsdKit (UTF-16) \ 😀'
            '\rDeuxième ligne';
        final PsdTypeTool edited = PsdTypeToolCodec.decode(PsdTypeToolCodec.encode(typeTool.withText(replacement)));
        if (edited.text == replacement && edited.content.text == replacement) {
          editableBlocks++;
        } else {
          stdout.writeln('TEXT EDIT ERROR\t${entity.path}\t${layer.name}');
        }
      }
    } on Object catch (error) {
      documentFailures++;
      stdout.writeln('PSD ERROR\t${entity.path}\t$error');
    }
  }
  stdout.writeln(
    'documents=$documents documentFailures=$documentFailures '
    'textBlocks=$textBlocks decoded=$decodedBlocks byteStable=$stableBlocks '
    'styled=$styledBlocks editable=$editableBlocks',
  );
  if (documentFailures != 0 || decodedBlocks != textBlocks || stableBlocks != decodedBlocks || editableBlocks != decodedBlocks) {
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

/// Returns the first differing byte offset, or the common length.
int _firstDifference(Uint8List first, Uint8List second) {
  final int length = first.length < second.length ? first.length : second.length;
  for (int index = 0; index < length; index++) {
    if (first[index] != second[index]) {
      return index;
    }
  }
  return length;
}

/// Formats a small byte window around [offset].
String _hexWindow(Uint8List bytes, int offset) {
  final int start = (offset - 4).clamp(0, bytes.length);
  final int end = (offset + 8).clamp(0, bytes.length);
  return Uint8List.sublistView(bytes, start, end).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');
}
