part of '../layer_comps.dart';

/// One entry inside Photoshop's `shmd` tagged block.
final class _SharedMetadataEntry {
  /// Four-byte vendor signature.
  final String signature;

  /// Four-byte metadata key.
  final String key;

  /// Whether Photoshop copies this metadata when duplicating the sheet.
  final bool copyOnSheetDuplication;

  /// Opaque entry payload without alignment padding.
  final Uint8List data;

  /// Creates one shared-metadata entry.
  const _SharedMetadataEntry({
    required this.signature,
    required this.key,
    required this.copyOnSheetDuplication,
    required this.data,
  });
}

/// Decodes a bounded Photoshop shared-metadata sequence.
List<_SharedMetadataEntry> _decodeSharedMetadata(Uint8List bytes) {
  final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
  final int count = reader.readUint32();
  if (count > _maximumLayerComps + _maximumExtraSharedMetadataEntries) {
    throw const PsFormatException(message: 'Too many shared metadata entries');
  }
  final List<_SharedMetadataEntry> entries = [];
  for (int index = 0; index < count; index++) {
    final String signature = reader.readString(4);
    final String key = reader.readString(4);
    final bool copyOnSheetDuplication = reader.readUint8() != 0;
    reader.skip(3);
    final int length = reader.readLength(
      wide: false,
      label: 'shared metadata',
    );
    entries.add(
      _SharedMetadataEntry(
        signature: signature,
        key: key,
        copyOnSheetDuplication: copyOnSheetDuplication,
        data: reader.readBytes(length),
      ),
    );
    if (length.isOdd) {
      reader.skip(1);
    }
  }
  if (!reader.isAtEnd && reader.readBytes(reader.remaining).any((byte) => byte != 0)) {
    throw const PsFormatException(
      message: 'Unexpected shared metadata bytes',
    );
  }
  return entries;
}

/// Encodes Photoshop shared metadata with even-sized entry padding.
Uint8List _encodeSharedMetadata(List<_SharedMetadataEntry> entries) {
  final PsBinaryWriter writer = PsBinaryWriter();
  writer.writeUint32(entries.length);
  for (final _SharedMetadataEntry entry in entries) {
    if (entry.signature.length != 4 || entry.key.length != 4) {
      throw const PsWriteException(
        message: 'Shared metadata signatures and keys must have four characters',
      );
    }
    writer
      ..writeString(entry.signature)
      ..writeString(entry.key)
      ..writeUint8(entry.copyOnSheetDuplication ? 1 : 0)
      ..writeZeros(3)
      ..writeUint32(entry.data.length)
      ..writeBytes(entry.data);
    if (entry.data.length.isOdd) {
      writer.writeUint8(0);
    }
  }
  return writer.takeBytes();
}

/// Returns a layer with one tagged-block key replaced or removed.
PsdLayer _copyLayerWithBlock(
  PsdLayer source,
  PsdTaggedBlock? replacement, {
  required String key,
}) => copyPsdLayer(
  source,
  additionalInfo: [
    for (final PsdTaggedBlock block in source.additionalInfo)
      if (block.key != key) block,
    ?replacement,
  ],
);

/// Builds a Photoshop point descriptor.
PsDescriptor _pointDescriptor(
  PsdLayerCompPoint point, {
  required bool integers,
}) => PsDescriptor(
  name: '\u0000',
  classId: 'null',
  items: [
    PsDescriptorItem(
      key: 'Hrzn',
      value: integers ? PsIntegerValue(value: point.horizontal.round()) : PsDoubleValue(value: point.horizontal),
    ),
    PsDescriptorItem(
      key: 'Vrtc',
      value: integers ? PsIntegerValue(value: point.vertical.round()) : PsDoubleValue(value: point.vertical),
    ),
  ],
);

/// Reads a finite point descriptor.
PsdLayerCompPoint? _point(PsDescriptorValue? value) {
  if (value is! PsObjectValue) {
    return null;
  }
  final double? horizontal = _number(value.value.value('Hrzn'));
  final double? vertical = _number(value.value.value('Vrtc'));
  return horizontal == null || vertical == null ? null : (horizontal: horizontal, vertical: vertical);
}

/// Reads the channel identifier from a Photoshop reference value.
String? _channelIdentifier(PsDescriptorValue? value) {
  if (value is! PsReferenceValue || value.values.length != 1) {
    return null;
  }
  return switch (value.values.single) {
    PsEnumeratedReferenceValue(
      classId: 'Chnl',
      typeId: 'Chnl',
      :final String value,
    ) =>
      value,
    _ => null,
  };
}

/// Reads a descriptor Boolean.
bool? _boolean(PsDescriptorValue? value) => value.asBoolean();

/// Reads a finite descriptor number.
double? _number(PsDescriptorValue? value) {
  final double? result = value.asNumber()?.value;
  return result?.isFinite ?? false ? result : null;
}

/// Reads a signed descriptor integer.
int? _integer(PsDescriptorValue? value) => value.asInteger();

/// Reads one enumeration with the expected type identifier.
String? _enumerated(PsDescriptorValue? value, {required String typeId}) {
  final PsDescriptorEnumeration? enumeration = value.asEnumeration();
  return enumeration?.typeId == typeId ? enumeration?.value : null;
}

/// Reads a finite percentage from a `#Prc` unit float.
double? _percentage(PsDescriptorValue? value) {
  final PsDescriptorNumber? number = value.asNumber();
  final double? percentage = number?.unit == '#Prc' ? number?.value : null;
  return percentage != null && percentage.isFinite && percentage >= 0 && percentage <= 100 ? percentage : null;
}

/// Validates one optional percentage before writing it.
void _validatePercentage(double? value, String label) {
  if (value != null && (!value.isFinite || value < 0 || value > 100)) {
    throw PsWriteException(message: '$label must be from 0 through 100');
  }
}

/// Whether the optional record point is absent or finite.
bool _validPoint(PsdLayerCompPoint? point) => point == null || point.horizontal.isFinite && point.vertical.isFinite;

/// Whether four values are ordered bytes.
bool _orderedBytes(int first, int second, int third, int fourth) => first >= 0 && first <= second && second <= third && third <= fourth && fourth <= 255;

/// Whether [value] fits Photoshop's signed descriptor integer.
bool _isSigned32(int value) => value >= -0x80000000 && value <= 0x7fffffff;
