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
        final ({PsDescriptor descriptor, int bytesRead}) decoded = PsDescriptorCodec.decodePrefix(Uint8List.sublistView(block.data, 8));
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
void _printDescriptor(PsDescriptor descriptor, String indent) {
  stdout.writeln('${indent}descriptor ${descriptor.classId} "${descriptor.name}"');
  for (final PsDescriptorItem item in descriptor.items) {
    stdout.write('$indent  ${item.key} ${item.value.type}');
    switch (item.value) {
      case PsBooleanValue(:final bool value):
        stdout.writeln(' $value');
      case PsIntegerValue(:final int value):
        stdout.writeln(' $value');
      case PsLargeIntegerValue(:final int value):
        stdout.writeln(' $value');
      case PsDoubleValue(:final double value):
        stdout.writeln(' $value');
      case PsUnitFloatValue(:final String unit, :final double value):
        stdout.writeln(' $value $unit');
      case PsUnitFloatsValue(:final String unit, :final List<double> values):
        stdout.writeln(' $values $unit');
      case PsStringValue(:final String value):
        stdout.writeln(' "$value"');
      case PsEnumeratedValue(:final String typeId, :final String value):
        stdout.writeln(' $typeId/$value');
      case PsObjectValue(:final PsDescriptor value):
        stdout.writeln();
        _printDescriptor(value, '$indent    ');
      case PsObjectArrayValue(:final int itemsCount, :final PsDescriptor value):
        stdout.writeln(' [$itemsCount]');
        _printDescriptor(value, '$indent    ');
      case PsListValue(:final List<PsDescriptorValue> values):
        stdout.writeln(' [${values.length}]');
        for (final PsDescriptorValue value in values) {
          if (value case PsObjectValue(:final PsDescriptor value)) {
            _printDescriptor(value, '$indent    ');
          }
        }
      case PsReferenceValue(:final List<PsDescriptorValue> values):
        stdout.writeln(' reference[${values.length}]');
      case PsPropertyValue(:final String classId, :final String keyId):
        stdout.writeln(' $classId/$keyId');
      case PsReferenceClassValue(:final String classId):
        stdout.writeln(' $classId');
      case PsEnumeratedReferenceValue(:final String classId, :final String typeId, :final String value):
        stdout.writeln(' $classId/$typeId/$value');
      case PsOffsetValue(:final String classId, :final int value):
        stdout.writeln(' $classId+$value');
      case PsIdentifierValue(:final int value):
        stdout.writeln(' $value');
      case PsIndexValue(:final int value):
        stdout.writeln(' $value');
      case PsNameValue(:final String classId, :final String value):
        stdout.writeln(' $classId/"$value"');
      case PsRawValue(:final Uint8List value):
        stdout.writeln(' ${value.length} bytes');
      case PsAliasValue(:final Uint8List value):
        stdout.writeln(' ${value.length} bytes');
      case PsPathValue(:final Uint8List value):
        stdout.writeln(' ${value.length} bytes');
      case PsClassValue(:final String classId):
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
