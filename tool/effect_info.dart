/// Prints raw layer-effect structures from a PSD or PSB file.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';

/// Decodes the command-line PSD and prints all effect descriptors.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/effect_info.dart <file.psd|file.psb>');
    exitCode = 64;
    return;
  }
  final PsdDocument document = PsdCodec.decode(await File(arguments.single).readAsBytes());
  for (final PsdLayer layer in document.layers) {
    for (final PsdTaggedBlock block in layer.additionalInfo) {
      if (block.key == 'lfx2' || block.key == 'lmfx') {
        stdout.writeln('${layer.name}: ${block.key}, ${block.data.length} bytes');
        if (block.data.length < 8) {
          continue;
        }
        final ByteData header = ByteData.sublistView(block.data);
        stdout.writeln('  version=${header.getUint32(0)}, descriptorVersion=${header.getUint32(4)}');
        final ({PsdDescriptor descriptor, int bytesRead}) decoded = PsdDescriptorCodec.decodePrefix(Uint8List.sublistView(block.data, 8));
        _printDescriptor(decoded.descriptor, '  ');
        stdout.writeln('  trailing=${block.data.length - 8 - decoded.bytesRead}');
      } else if (block.key == 'lrFX') {
        stdout.writeln('${layer.name}: lrFX, ${block.data.length} bytes');
        _printLegacy(block.data);
      }
    }
  }
}

/// Prints [descriptor] and all nested descriptor values.
void _printDescriptor(PsdDescriptor descriptor, String indent) {
  stdout.writeln('${indent}descriptor ${descriptor.classId} "${descriptor.name}"');
  for (final PsdDescriptorItem item in descriptor.items) {
    stdout.write('$indent  ${item.key} ${item.value.type}');
    switch (item.value) {
      case PsdBooleanValue(:final bool value):
        stdout.writeln(' $value');
      case PsdIntegerValue(:final int value):
        stdout.writeln(' $value');
      case PsdLargeIntegerValue(:final int value):
        stdout.writeln(' $value');
      case PsdDoubleValue(:final double value):
        stdout.writeln(' $value');
      case PsdUnitFloatValue(:final String unit, :final double value):
        stdout.writeln(' $value $unit');
      case PsdUnitFloatsValue(:final String unit, :final List<double> values):
        stdout.writeln(' $values $unit');
      case PsdStringValue(:final String value):
        stdout.writeln(' "$value"');
      case PsdEnumeratedValue(:final String typeId, :final String value):
        stdout.writeln(' $typeId/$value');
      case PsdObjectValue(:final PsdDescriptor value):
        stdout.writeln();
        _printDescriptor(value, '$indent    ');
      case PsdObjectArrayValue(:final int itemsCount, :final PsdDescriptor value):
        stdout.writeln(' [$itemsCount]');
        _printDescriptor(value, '$indent    ');
      case PsdListValue(:final List<PsdDescriptorValue> values):
        stdout.writeln(' [${values.length}]');
        for (final PsdDescriptorValue value in values) {
          if (value case PsdObjectValue(:final PsdDescriptor value)) {
            _printDescriptor(value, '$indent    ');
          }
        }
      case PsdRawValue(:final Uint8List value):
        stdout.writeln(' ${value.length} bytes');
      case PsdAliasValue(:final Uint8List value):
        stdout.writeln(' ${value.length} bytes');
      case PsdClassValue(:final String classId):
        stdout.writeln(' $classId');
    }
  }
}

/// Prints the keys and sizes in a legacy `lrFX` payload.
void _printLegacy(Uint8List bytes) {
  if (bytes.length < 4) {
    return;
  }
  final ByteData data = ByteData.sublistView(bytes);
  int offset = 0;
  final int version = data.getUint16(offset);
  offset += 2;
  final int count = data.getUint16(offset);
  offset += 2;
  stdout.writeln('  version=$version, count=$count');
  for (int index = 0; index < count && offset + 12 <= bytes.length; index++) {
    final String signature = String.fromCharCodes(Uint8List.sublistView(bytes, offset, offset + 4));
    final String key = String.fromCharCodes(Uint8List.sublistView(bytes, offset + 4, offset + 8));
    final int length = data.getUint32(offset + 8);
    stdout.writeln('  $signature/$key: $length bytes');
    offset += 12 + length;
  }
  stdout.writeln('  trailing=${bytes.length - offset}');
}
