/// Audits layer-effect decoding, editing, and lossless re-encoding in a PSD corpus.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';

/// Scans the directory passed on the command line and prints effect statistics.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/effects_corpus_check.dart <directory>');
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
  int modernBlocks = 0;
  int legacyBlocks = 0;
  int decodedBlocks = 0;
  int stableBlocks = 0;
  int editableBlocks = 0;
  int semanticEffects = 0;
  await for (final FileSystemEntity entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File || !_isPhotoshopPath(entity.path)) {
      continue;
    }
    documents++;
    try {
      final PsdDocument document = PsdCodec.decode(await entity.readAsBytes());
      for (final PsdLayer layer in document.layers) {
        for (final PsdTaggedBlock block in layer.additionalInfo) {
          if (block.key != 'lfx2' && block.key != 'lmfx' && block.key != 'lrFX') {
            continue;
          }
          blocks++;
          if (block.key == 'lrFX') {
            legacyBlocks++;
          } else {
            modernBlocks++;
          }
          final PsdLayerEffects? effects = PsdLayerEffectsCodec.tryDecode(block.data, key: block.key);
          if (effects == null) {
            stdout.writeln('EFFECT ERROR\t${entity.path}\t${layer.name}\t${block.key}');
            continue;
          }
          decodedBlocks++;
          semanticEffects += effects.effects.length;
          if (_equalBytes(block.data, PsdLayerEffectsCodec.encode(effects))) {
            stableBlocks++;
          } else {
            stdout.writeln('EFFECT CHANGED\t${entity.path}\t${layer.name}\t${block.key}');
          }
          final PsdLayerEffects edited = effects.effects.isEmpty
              ? effects.withEnabled(!effects.enabled)
              : effects.withEffects(<PsdLayerEffect>[for (final PsdLayerEffect effect in effects.effects) effect.withOpacity(37.5)]);
          final PsdLayerEffects? decodedEdit = PsdLayerEffectsCodec.tryDecode(
            PsdLayerEffectsCodec.encode(edited),
            key: edited.blockKey,
          );
          if (decodedEdit != null && (effects.effects.isEmpty || decodedEdit.effects.every((effect) => effect.opacity == 37.5))) {
            editableBlocks++;
          } else {
            stdout.writeln('EFFECT EDIT ERROR\t${entity.path}\t${layer.name}\t${block.key}');
          }
        }
      }
    } on Object catch (error) {
      documentFailures++;
      stdout.writeln('PSD ERROR\t${entity.path}\t$error');
    }
  }
  stdout.writeln(
    'documents=$documents documentFailures=$documentFailures blocks=$blocks '
    'modern=$modernBlocks legacy=$legacyBlocks decoded=$decodedBlocks '
    'byteStable=$stableBlocks editable=$editableBlocks semanticEffects=$semanticEffects',
  );
  if (documentFailures != 0 || decodedBlocks != blocks || stableBlocks != decodedBlocks || editableBlocks != decodedBlocks) {
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
