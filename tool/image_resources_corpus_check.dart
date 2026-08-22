/// Audits semantic image-resource decoding and byte-stable encoding.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';

/// Undocumented resource id observed in the reference corpus.
const int _corpusUndocumentedResourceId = 1092;

/// Scans one PSD directory and validates every image-resource payload.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/image_resources_corpus_check.dart <directory>');
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
  int resources = 0;
  int semantic = 0;
  int binary = 0;
  int raw = 0;
  int standardRaw = 0;
  int byteStable = 0;
  final Map<int, int> rawIds = <int, int>{};
  final Map<String, int> types = <String, int>{};
  await for (final FileSystemEntity entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File || !_isPhotoshopPath(entity.path)) {
      continue;
    }
    documents++;
    try {
      final PsdDocument document = PsdCodec.decode(await entity.readAsBytes());
      for (final PsdImageResource resource in document.imageResources) {
        resources++;
        final PsdImageResourceData decoded = resource.decoded;
        types.update(decoded.runtimeType.toString(), (count) => count + 1, ifAbsent: () => 1);
        switch (decoded) {
          case PsdRawImageResource():
            raw++;
            rawIds.update(resource.id, (count) => count + 1, ifAbsent: () => 1);
            if (!PsdImageResourceIds.isPlugin(resource.id) && resource.id != _corpusUndocumentedResourceId) {
              standardRaw++;
              try {
                PsdImageResourceCodec.decode(resource.data, resourceId: resource.id);
              } on Object catch (error) {
                stdout.writeln('STANDARD RAW\t${entity.path}\t${resource.id}\t${resource.data.length}\t$error');
              }
            }
          case PsdBinaryMetadataResource():
            binary++;
          default:
            semantic++;
        }
        final Uint8List encoded = PsdImageResourceCodec.encode(decoded);
        if (_equalBytes(resource.data, encoded)) {
          byteStable++;
        } else {
          stdout.writeln('RESOURCE CHANGED\t${entity.path}\t${resource.id}\t${decoded.runtimeType}\t${resource.data.length}->${encoded.length}');
        }
      }
    } on Object catch (error) {
      documentFailures++;
      stdout.writeln('PSD ERROR\t${entity.path}\t$error');
    }
  }
  stdout.writeln(
    'documents=$documents documentFailures=$documentFailures resources=$resources '
    'semantic=$semantic binary=$binary raw=$raw standardRaw=$standardRaw byteStable=$byteStable '
    'rawIds=${_mapSummary(rawIds)} types=${_mapSummary(types)}',
  );
  if (documentFailures != 0 || standardRaw != 0 || byteStable != resources) {
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

/// Formats a sorted map for the final summary.
String _mapSummary<K>(Map<K, int> map) {
  final List<MapEntry<K, int>> entries = map.entries.toList()..sort((left, right) => left.key.toString().compareTo(right.key.toString()));
  return entries.map((entry) => '${entry.key}:${entry.value}').join(',');
}
