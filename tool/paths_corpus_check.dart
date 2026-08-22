/// Audits vector-mask and document-path support in a PSD corpus.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';

/// Scans the directory passed on the command line and prints vector-path statistics.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/paths_corpus_check.dart <directory>');
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
  int maskBlocks = 0;
  int decodedMasks = 0;
  int stableMasks = 0;
  int editableMasks = 0;
  int namedPaths = 0;
  int decodedPaths = 0;
  int stablePaths = 0;
  int subpaths = 0;
  int knots = 0;
  int unknownRecords = 0;
  await for (final FileSystemEntity entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File || !_isPhotoshopPath(entity.path)) {
      continue;
    }
    documents++;
    try {
      final PsdDocument document = PsdCodec.decode(await entity.readAsBytes());
      for (final PsdLayer layer in document.layers) {
        for (final PsdTaggedBlock block in layer.additionalInfo) {
          if (block.key != 'vmsk' && block.key != 'vsms') {
            continue;
          }
          maskBlocks++;
          final PsdVectorMask? mask = PsdVectorMaskCodec.tryDecode(block.data, key: block.key);
          if (mask == null) {
            stdout.writeln('MASK ERROR\t${entity.path}\t${layer.name}\t${block.key}\t${block.data.length}');
            continue;
          }
          decodedMasks++;
          if (_equalBytes(block.data, PsdVectorMaskCodec.encode(mask))) {
            stableMasks++;
          } else {
            stdout.writeln('MASK CHANGED\t${entity.path}\t${layer.name}\t${block.key}');
          }
          _countPath(mask.path, onSubpath: () => subpaths++, onKnot: () => knots++, onUnknown: () => unknownRecords++);
          final PsdVectorMask edited = PsdVectorMask(
            version: mask.version,
            flags: mask.flags ^ 1,
            path: mask.path.withSubpaths(mask.path.subpaths),
            blockKey: mask.blockKey,
            trailingData: mask.trailingData,
          );
          final PsdVectorMask? decodedEdit = PsdVectorMaskCodec.tryDecode(PsdVectorMaskCodec.encode(edited), key: edited.blockKey);
          if (decodedEdit != null && decodedEdit.path.subpaths.length == mask.path.subpaths.length) {
            editableMasks++;
          } else {
            stdout.writeln('MASK EDIT ERROR\t${entity.path}\t${layer.name}\t${block.key}');
          }
        }
      }
      for (final PsdImageResource resource in document.imageResources) {
        if (resource.id < 2000 || resource.id > 2997) {
          continue;
        }
        namedPaths++;
        final PsdVectorPath? path = PsdVectorPathCodec.tryDecode(resource.data);
        if (path == null) {
          stdout.writeln('PATH ERROR\t${entity.path}\t${resource.id}\t${resource.name}\t${resource.data.length}');
          continue;
        }
        decodedPaths++;
        if (_equalBytes(resource.data, PsdVectorPathCodec.encode(path))) {
          stablePaths++;
        } else {
          stdout.writeln('PATH CHANGED\t${entity.path}\t${resource.id}\t${resource.name}');
        }
        _countPath(path, onSubpath: () => subpaths++, onKnot: () => knots++, onUnknown: () => unknownRecords++);
      }
    } on Object catch (error) {
      documentFailures++;
      stdout.writeln('PSD ERROR\t${entity.path}\t$error');
    }
  }
  stdout.writeln(
    'documents=$documents documentFailures=$documentFailures maskBlocks=$maskBlocks '
    'decodedMasks=$decodedMasks byteStableMasks=$stableMasks editableMasks=$editableMasks '
    'namedPaths=$namedPaths decodedPaths=$decodedPaths byteStablePaths=$stablePaths '
    'subpaths=$subpaths knots=$knots unknownRecords=$unknownRecords',
  );
  if (documentFailures != 0 || decodedMasks != maskBlocks || stableMasks != decodedMasks || editableMasks != decodedMasks || decodedPaths != namedPaths || stablePaths != decodedPaths) {
    exitCode = 1;
  }
}

/// Counts semantic and unknown records in [path].
void _countPath(
  PsdVectorPath path, {
  required void Function() onSubpath,
  required void Function() onKnot,
  required void Function() onUnknown,
}) {
  for (final PsdSubpath subpath in path.subpaths) {
    onSubpath();
    for (final PsdBezierKnot _ in subpath.knots) {
      onKnot();
    }
  }
  for (final PsdPathRecord record in path.records) {
    if (record is PsdUnknownPathRecord) {
      onUnknown();
    }
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
