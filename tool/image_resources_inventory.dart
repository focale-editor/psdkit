/// Inventories Photoshop image-resource identifiers in a PSD corpus.
library;

import 'dart:io';

import 'package:psdkit/psdkit.dart';

/// Scans one directory and reports resource counts and payload sizes by id.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/image_resources_inventory.dart <directory>');
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
  int failures = 0;
  final Map<int, _ResourceStats> statistics = <int, _ResourceStats>{};
  await for (final FileSystemEntity entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File || !_isPhotoshopPath(entity.path)) {
      continue;
    }
    documents++;
    try {
      final PsdDocument document = PsdCodec.decode(await entity.readAsBytes());
      for (final PsdImageResource resource in document.imageResources) {
        statistics.putIfAbsent(resource.id, _ResourceStats.new).add(resource);
      }
    } on Object catch (error) {
      failures++;
      stdout.writeln('PSD ERROR\t${entity.path}\t$error');
    }
  }
  final List<int> ids = statistics.keys.toList()..sort();
  for (final int id in ids) {
    final _ResourceStats stats = statistics[id]!;
    stdout.writeln('$id\tcount=${stats.count}\tsizes=${stats.sizes.join(',')}\tnames=${stats.names.join('|')}');
  }
  stdout.writeln('documents=$documents failures=$failures resourceIds=${ids.length} resources=${statistics.values.fold<int>(0, (sum, value) => sum + value.count)}');
  if (failures != 0) {
    exitCode = 1;
  }
}

/// Whether [path] has a PSD or PSB extension.
bool _isPhotoshopPath(String path) {
  final String lower = path.toLowerCase();
  return lower.endsWith('.psd') || lower.endsWith('.psb');
}

/// Aggregates occurrences and representative metadata for one resource id.
final class _ResourceStats {
  /// Number of resource blocks.
  int count = 0;

  /// Distinct payload sizes, capped for readable output.
  final Set<int> sizes = <int>{};

  /// Distinct non-empty resource names, capped for readable output.
  final Set<String> names = <String>{};

  /// Creates empty statistics.
  _ResourceStats();

  /// Records one [resource].
  void add(PsdImageResource resource) {
    count++;
    if (sizes.length < 20) {
      sizes.add(resource.data.length);
    }
    if (resource.name.isNotEmpty && names.length < 10) {
      names.add(resource.name);
    }
  }
}
