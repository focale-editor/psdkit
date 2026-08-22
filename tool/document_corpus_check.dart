/// Audits complete PSD/PSB model stability across an import/export cycle.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';

/// Scans a directory and verifies every complete document after re-encoding.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/document_corpus_check.dart <directory>');
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
  int decodeFailures = 0;
  int encodeFailures = 0;
  int stableDocuments = 0;
  int layeredHighDepthDocuments = 0;
  int alternateLayerBlocks = 0;
  final Map<int, int> depths = <int, int>{};
  final Map<PsdVersion, int> versions = <PsdVersion, int>{};
  final Map<PsdCompression, int> mergedCompressions = <PsdCompression, int>{};
  await for (final FileSystemEntity entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File || !_isPhotoshopPath(entity.path)) {
      continue;
    }
    documents++;
    try {
      final PsdDocument source = PsdCodec.decode(await entity.readAsBytes());
      depths.update(source.depth, (count) => count + 1, ifAbsent: () => 1);
      versions.update(source.version, (count) => count + 1, ifAbsent: () => 1);
      mergedCompressions.update(source.mergedImageCompression, (count) => count + 1, ifAbsent: () => 1);
      if (source.depth > 8 && source.layers.isNotEmpty) {
        layeredHighDepthDocuments++;
      }
      alternateLayerBlocks += source.additionalLayerInfo.where((block) => const <String>{'Layr', 'Lr16', 'Lr32'}.contains(block.key)).length;
      try {
        final PsdDocument decoded = PsdCodec.decode(PsdCodec.encode(source));
        final String? difference = _documentDifference(source, decoded);
        if (difference == null) {
          stableDocuments++;
        } else {
          encodeFailures++;
          stdout.writeln('ROUNDTRIP ERROR\t${entity.path}\t$difference');
        }
      } on Object catch (error) {
        encodeFailures++;
        stdout.writeln('ENCODE ERROR\t${entity.path}\t$error');
      }
    } on Object catch (error) {
      decodeFailures++;
      stdout.writeln('DECODE ERROR\t${entity.path}\t$error');
    }
  }
  stdout.writeln(
    'documents=$documents decodeFailures=$decodeFailures encodeFailures=$encodeFailures '
    'stable=$stableDocuments layeredHighDepth=$layeredHighDepthDocuments '
    'alternateLayerBlocks=$alternateLayerBlocks depths=${_mapSummary(depths)} '
    'versions=${_mapSummary(versions)} mergedCompression=${_mapSummary(mergedCompressions)}',
  );
  if (decodeFailures != 0 || encodeFailures != 0 || stableDocuments != documents) {
    exitCode = 1;
  }
}

/// Returns the first semantic or loss-preservation difference between documents.
String? _documentDifference(PsdDocument first, PsdDocument second) {
  if (first.version != second.version ||
      first.width != second.width ||
      first.height != second.height ||
      first.channels != second.channels ||
      first.depth != second.depth ||
      first.colorMode != second.colorMode ||
      first.mergedImageCompression != second.mergedImageCompression ||
      first.mergedTransparency != second.mergedTransparency) {
    return 'document metadata changed';
  }
  if (!_equalBytes(first.colorModeData, second.colorModeData)) {
    return 'color-mode data changed';
  }
  if (!_equalResources(first.imageResources, second.imageResources)) {
    return 'image resources changed';
  }
  if (!_equalLayers(first.layers, second.layers)) {
    return 'layers changed';
  }
  if (!_equalByteLists(first.mergedImage, second.mergedImage)) {
    return 'merged image changed';
  }
  if (!_equalBytes(first.globalLayerMaskData, second.globalLayerMaskData)) {
    return 'global layer mask changed';
  }
  if (!_equalBlocks(_nonLayerBlocks(first.additionalLayerInfo), _nonLayerBlocks(second.additionalLayerInfo))) {
    return 'document tagged blocks changed';
  }
  return null;
}

/// Excludes depth-specific layer-info blocks represented by [PsdDocument.layers].
List<PsdTaggedBlock> _nonLayerBlocks(List<PsdTaggedBlock> blocks) => <PsdTaggedBlock>[
  for (final PsdTaggedBlock block in blocks)
    if (!const <String>{'Layr', 'Lr16', 'Lr32'}.contains(block.key)) block,
];

/// Whether [path] has a PSD or PSB extension.
bool _isPhotoshopPath(String path) {
  final String lower = path.toLowerCase();
  return lower.endsWith('.psd') || lower.endsWith('.psb');
}

/// Whether complete image-resource lists are identical.
bool _equalResources(List<PsdImageResource> first, List<PsdImageResource> second) {
  if (first.length != second.length) {
    return false;
  }
  for (int index = 0; index < first.length; index++) {
    final PsdImageResource left = first[index];
    final PsdImageResource right = second[index];
    if (left.id != right.id || left.name != right.name || left.signature != right.signature || !_equalBytes(left.data, right.data)) {
      return false;
    }
  }
  return true;
}

/// Whether layer records and all decoded channel samples are identical.
bool _equalLayers(List<PsdLayer> first, List<PsdLayer> second) {
  if (first.length != second.length) {
    return false;
  }
  for (int index = 0; index < first.length; index++) {
    final PsdLayer left = first[index];
    final PsdLayer right = second[index];
    if (!_equalRectangle(left.rectangle, right.rectangle) ||
        left.name != right.name ||
        left.blendMode != right.blendMode ||
        left.opacity != right.opacity ||
        left.clipping != right.clipping ||
        left.flags != right.flags ||
        !_equalBytes(left.mask?.data, right.mask?.data) ||
        !_equalBytes(left.blendingRanges, right.blendingRanges) ||
        !_equalChannels(left.channels, right.channels) ||
        !_equalBlocks(
          left.additionalInfo.where((block) => block.key != 'luni').toList(),
          right.additionalInfo.where((block) => block.key != 'luni').toList(),
        )) {
      return false;
    }
  }
  return true;
}

/// Whether channel ids, encodings, and decoded samples are identical.
bool _equalChannels(List<PsdChannel> first, List<PsdChannel> second) {
  if (first.length != second.length) {
    return false;
  }
  for (int index = 0; index < first.length; index++) {
    final PsdChannel left = first[index];
    final PsdChannel right = second[index];
    if (left.id != right.id || left.compression != right.compression || !_equalBytes(left.data, right.data)) {
      return false;
    }
  }
  return true;
}

/// Whether tagged blocks retain their order, signatures, keys, and data.
bool _equalBlocks(List<PsdTaggedBlock> first, List<PsdTaggedBlock> second) {
  if (first.length != second.length) {
    return false;
  }
  for (int index = 0; index < first.length; index++) {
    final PsdTaggedBlock left = first[index];
    final PsdTaggedBlock right = second[index];
    if (left.key != right.key || left.signature != right.signature || !_equalBytes(left.data, right.data)) {
      return false;
    }
  }
  return true;
}

/// Whether rectangle edges are identical.
bool _equalRectangle(PsdRectangle first, PsdRectangle second) => first.top == second.top && first.left == second.left && first.bottom == second.bottom && first.right == second.right;

/// Whether lists of byte planes are identical.
bool _equalByteLists(List<Uint8List> first, List<Uint8List> second) {
  if (first.length != second.length) {
    return false;
  }
  for (int index = 0; index < first.length; index++) {
    if (!_equalBytes(first[index], second[index])) {
      return false;
    }
  }
  return true;
}

/// Whether nullable byte arrays contain identical values.
bool _equalBytes(Uint8List? first, Uint8List? second) {
  if (first == null || second == null) {
    return first == null && second == null;
  }
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

/// Formats a sorted count map for the final audit summary.
String _mapSummary<K>(Map<K, int> map) {
  final List<MapEntry<K, int>> entries = map.entries.toList()..sort((left, right) => left.key.toString().compareTo(right.key.toString()));
  return entries.map((entry) => '${entry.key}: ${entry.value}').join(',');
}
