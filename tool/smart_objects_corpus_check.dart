/// Audits smart-object and linked-resource support in a PSD corpus.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';

/// Scans the directory passed on the command line and prints smart-object statistics.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/smart_objects_corpus_check.dart <directory>');
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
  int layerBlocks = 0;
  int semanticLayerBlocks = 0;
  int stableLayerBlocks = 0;
  int linkedBlocks = 0;
  int stableLinkedBlocks = 0;
  int linkedEntries = 0;
  int semanticLinkedEntries = 0;
  int embeddedResources = 0;
  int externalResources = 0;
  int aliasResources = 0;
  int smartObjectReferences = 0;
  int resolvedReferences = 0;
  final Map<String, int> layerKeys = <String, int>{};
  final Map<String, int> linkedKeys = <String, int>{};
  final Map<int, int> linkedVersions = <int, int>{};
  await for (final FileSystemEntity entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File || !_isPhotoshopPath(entity.path)) {
      continue;
    }
    documents++;
    try {
      final PsdDocument document = PsdCodec.decode(await entity.readAsBytes());
      final Map<String, PsdLinkedResource> resourcesById = <String, PsdLinkedResource>{};
      for (final PsdTaggedBlock block in document.additionalLayerInfo) {
        if (!psdLinkedResourceKeys.contains(block.key)) {
          continue;
        }
        linkedBlocks++;
        linkedKeys.update(block.key, (count) => count + 1, ifAbsent: () => 1);
        final PsdLinkedResourceBlock? decoded = PsdLinkedResourceCodec.tryDecode(block.data, key: block.key);
        if (decoded == null) {
          stdout.writeln('LINKED BLOCK ERROR\t${entity.path}\t${block.key}');
          continue;
        }
        if (_equalBytes(block.data, PsdLinkedResourceCodec.encode(decoded))) {
          stableLinkedBlocks++;
        } else {
          stdout.writeln('LINKED BLOCK CHANGED\t${entity.path}\t${block.key}');
        }
        linkedEntries += decoded.entries.length;
        semanticLinkedEntries += decoded.resources.length;
        for (final PsdLinkedResource resource in decoded.resources) {
          resourcesById[resource.id] = resource;
          linkedVersions.update(resource.version, (count) => count + 1, ifAbsent: () => 1);
          switch (resource.type) {
            case PsdLinkedResourceType.embedded:
              embeddedResources++;
            case PsdLinkedResourceType.external:
              externalResources++;
            case PsdLinkedResourceType.alias:
              aliasResources++;
          }
        }
      }
      for (final PsdLayer layer in document.layers) {
        for (final PsdTaggedBlock block in layer.additionalInfo) {
          if (!psdSmartObjectLayerKeys.contains(block.key)) {
            continue;
          }
          layerBlocks++;
          layerKeys.update(block.key, (count) => count + 1, ifAbsent: () => 1);
          final PsdSmartObjectLayerData? decoded = PsdSmartObjectCodec.tryDecode(block.data, key: block.key);
          if (decoded == null) {
            stdout.writeln('SMART OBJECT ERROR\t${entity.path}\t${layer.name}\t${block.key}');
            continue;
          }
          if (decoded is PsdRawSmartObject) {
            stdout.writeln('RAW SMART OBJECT\t${entity.path}\t${layer.name}\t${block.key}\t${block.data.length} bytes');
          } else {
            semanticLayerBlocks++;
          }
          if (_equalBytes(block.data, PsdSmartObjectCodec.encode(decoded))) {
            stableLayerBlocks++;
          } else {
            stdout.writeln('SMART OBJECT CHANGED\t${entity.path}\t${layer.name}\t${block.key}');
          }
          final String? id = decoded.linkedResourceId;
          if (id != null) {
            smartObjectReferences++;
            if (resourcesById.containsKey(id)) {
              resolvedReferences++;
            }
          }
        }
      }
    } on Object catch (error) {
      documentFailures++;
      stdout.writeln('PSD ERROR\t${entity.path}\t$error');
    }
  }
  stdout.writeln(
    'documents=$documents documentFailures=$documentFailures '
    'layerBlocks=$layerBlocks semanticLayers=$semanticLayerBlocks byteStableLayers=$stableLayerBlocks '
    'linkedBlocks=$linkedBlocks byteStableLinkedBlocks=$stableLinkedBlocks '
    'linkedEntries=$linkedEntries semanticEntries=$semanticLinkedEntries '
    'embedded=$embeddedResources external=$externalResources alias=$aliasResources '
    'references=$smartObjectReferences resolved=$resolvedReferences '
    'layerKeys=${_mapSummary(layerKeys)} linkedKeys=${_mapSummary(linkedKeys)} versions=${_mapSummary(linkedVersions)}',
  );
  if (documentFailures != 0 || stableLayerBlocks != layerBlocks || stableLinkedBlocks != linkedBlocks) {
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

/// Formats a sorted key/count [map].
String _mapSummary<K extends Comparable<K>>(Map<K, int> map) {
  final List<K> keys = map.keys.toList()..sort();
  return <String>[for (final K key in keys) '$key:${map[key]}'].join(',');
}
