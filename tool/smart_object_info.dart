/// Prints raw smart-object and linked-resource blocks from PSD or PSB files.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';

/// Smart-object layer keys inspected by this tool.
const Set<String> _layerKeys = <String>{'SoLd', 'SoLE', 'plLd'};

/// Linked-resource document keys inspected by this tool.
const Set<String> _documentKeys = <String>{'lnkD', 'lnk2', 'lnk3'};

/// Decodes input paths or directories and prints smart-object payloads.
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln('Usage: dart run tool/smart_object_info.dart <file-or-directory> [...]');
    exitCode = 64;
    return;
  }
  final List<String> paths = <String>[];
  for (final String argument in arguments) {
    if (FileSystemEntity.typeSync(argument) == FileSystemEntityType.directory) {
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
    try {
      final PsdDocument document = PsdCodec.decode(await File(path).readAsBytes());
      for (final PsdLayer layer in document.layers) {
        for (final PsdTaggedBlock block in layer.additionalInfo) {
          if (_layerKeys.contains(block.key)) {
            stdout.writeln('$path\tlayer\t${layer.name}\t${block.key}\t${block.data.length}\t${_hex(block.data)}');
            final PsdSmartObjectLayerData smartObject = PsdSmartObjectCodec.decode(block.data, key: block.key);
            stdout.writeln(
              '  smart=${smartObject.runtimeType} id=${smartObject.linkedResourceId} '
              'stable=${_equalBytes(block.data, PsdSmartObjectCodec.encode(smartObject))}',
            );
            if (block.key == 'SoLd' && block.data.length > 12) {
              try {
                final ({PsdDescriptor descriptor, int bytesRead}) decoded = PsdDescriptorCodec.decodePrefix(
                  Uint8List.sublistView(block.data, 12),
                );
                stdout.writeln(
                  '  descriptor=${decoded.descriptor.classId} items=${decoded.descriptor.items.length} '
                  'bytes=${decoded.bytesRead} trailing=${block.data.length - 12 - decoded.bytesRead}',
                );
              } on Object catch (error) {
                stdout.writeln('  descriptor-error=$error');
              }
            }
          }
        }
      }
      for (final PsdTaggedBlock block in document.additionalLayerInfo) {
        if (_documentKeys.contains(block.key)) {
          stdout.writeln('$path\tdocument\t${block.key}\t${block.data.length}\t${_hex(block.data)}');
          final PsdLinkedResourceBlock resources = PsdLinkedResourceCodec.decode(block.data, key: block.key);
          stdout.writeln(
            '  entries=${resources.entries.length} semantic=${resources.resources.length} '
            'stable=${_equalBytes(block.data, PsdLinkedResourceCodec.encode(resources))}',
          );
          if (resources.resources.isEmpty && block.data.length >= 8) {
            final int length = ByteData.sublistView(block.data).getUint64(0);
            try {
              final PsdLinkedResource resource = PsdLinkedResourceCodec.decodeEntry(
                Uint8List.sublistView(block.data, 8, 8 + length),
              );
              stdout.writeln('  direct=${resource.type.name}/${resource.version}/${resource.name}');
            } on Object catch (error) {
              stdout.writeln('  entry-error=$error');
            }
          }
        }
      }
    } on Object catch (error) {
      stderr.writeln('$path\t$error');
    }
  }
}

/// Whether [path] has a PSD or PSB extension.
bool _isPhotoshopPath(String path) {
  final String lower = path.toLowerCase();
  return lower.endsWith('.psd') || lower.endsWith('.psb');
}

/// Returns a bounded hexadecimal preview of [bytes].
String _hex(Uint8List bytes) {
  final int length = bytes.length.clamp(0, 96);
  return <String>[for (int index = 0; index < length; index++) bytes[index].toRadixString(16).padLeft(2, '0')].join(' ');
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
