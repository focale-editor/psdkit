/// Prints raw adjustment-layer blocks from a PSD or PSB file.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';

/// Adjustment block keys recognized by this inspection tool.
const Set<String> _adjustmentKeys = <String>{
  'brit',
  'levl',
  'curv',
  'expA',
  'vibA',
  'hue ',
  'hue2',
  'blnc',
  'blwh',
  'phfl',
  'mixr',
  'clrL',
  'nvrt',
  'post',
  'thrs',
  'grdm',
  'selc',
};

/// Decodes the command-line PSD and prints its adjustment payloads.
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln('Usage: dart run tool/adjustment_info.dart <file.psd|file.psb> [...]');
    exitCode = 64;
    return;
  }
  final List<String> paths = <String>[];
  for (final String argument in arguments) {
    final FileSystemEntityType type = FileSystemEntity.typeSync(argument);
    if (type == FileSystemEntityType.directory) {
      await for (final FileSystemEntity entity in Directory(argument).list(recursive: true, followLinks: false)) {
        if (entity is File && _isPhotoshopPath(entity.path)) {
          paths.add(entity.path);
        }
      }
    } else {
      paths.add(argument);
    }
  }
  for (final String path in paths) {
    final PsdDocument document;
    try {
      document = PsdCodec.decode(await File(path).readAsBytes());
    } on Object catch (error) {
      stderr.writeln('$path\t$error');
      continue;
    }
    for (final PsdLayer layer in document.layers) {
      for (final PsdTaggedBlock block in layer.additionalInfo) {
        if (!_adjustmentKeys.contains(block.key)) {
          continue;
        }
        stdout.writeln('$path\t${layer.name}\t${block.key}\t${block.data.length}\t${_hex(block.data)}');
        _tryDescriptors(block.data);
      }
    }
  }
}

/// Whether [path] names a PSD or PSB file.
bool _isPhotoshopPath(String path) {
  final String lower = path.toLowerCase();
  return lower.endsWith('.psd') || lower.endsWith('.psb');
}

/// Returns a bounded hexadecimal preview of [bytes].
String _hex(Uint8List bytes) {
  final int length = bytes.length.clamp(0, 96);
  return <String>[for (int index = 0; index < length; index++) bytes[index].toRadixString(16).padLeft(2, '0')].join(' ');
}

/// Reports descriptor prefixes found at conventional adjustment offsets.
void _tryDescriptors(Uint8List bytes) {
  for (final int offset in const <int>[0, 2, 4, 8]) {
    if (offset >= bytes.length) {
      continue;
    }
    try {
      final ({PsdDescriptor descriptor, int bytesRead}) decoded = PsdDescriptorCodec.decodePrefix(Uint8List.sublistView(bytes, offset));
      stdout.writeln('  descriptor@$offset class=${decoded.descriptor.classId} items=${decoded.descriptor.items.length} bytes=${decoded.bytesRead}');
    } on Object {
      // Most binary adjustment payloads are intentionally not descriptors.
    }
  }
}
