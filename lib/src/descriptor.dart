import 'dart:typed_data';

import 'package:psdkit/src/binary.dart';
import 'package:psdkit/src/exceptions.dart';

/// A Photoshop action descriptor containing ordered, typed items.
final class PsdDescriptor {
  /// Human-readable class name, which is often empty.
  final String name;

  /// Photoshop class identifier.
  final String classId;

  /// Ordered descriptor items.
  final List<PsdDescriptorItem> items;

  /// Whether [classId] used the compact zero-length representation.
  final bool _compactClassId;

  /// Creates an action descriptor.
  const PsdDescriptor({required this.name, required this.classId, this.items = const <PsdDescriptorItem>[], this._compactClassId = true});

  /// Returns the last item matching [key], when present.
  PsdDescriptorValue? value(String key) {
    for (final PsdDescriptorItem item in items.reversed) {
      if (item.key == key) {
        return item.value;
      }
    }
    return null;
  }

  /// Returns a copy where [key] contains [value].
  PsdDescriptor withValue(String key, PsdDescriptorValue value) {
    final List<PsdDescriptorItem> updated = <PsdDescriptorItem>[];
    bool replaced = false;
    for (final PsdDescriptorItem item in items) {
      if (item.key == key) {
        if (!replaced) {
          updated.add(PsdDescriptorItem(key: key, value: value, compactKey: item._compactKey));
        }
        replaced = true;
      } else {
        updated.add(item);
      }
    }
    if (!replaced) {
      updated.add(PsdDescriptorItem(key: key, value: value));
    }
    return PsdDescriptor(name: name, classId: classId, items: updated, compactClassId: _compactClassId);
  }
}

/// One keyed value inside a Photoshop action descriptor.
final class PsdDescriptorItem {
  /// Photoshop key identifier.
  final String key;

  /// Typed value associated with [key].
  final PsdDescriptorValue value;

  /// Whether [key] used the compact zero-length representation.
  final bool _compactKey;

  /// Creates a keyed descriptor item.
  const PsdDescriptorItem({required this.key, required this.value, this._compactKey = true});
}

/// Base type for Photoshop action-descriptor values.
sealed class PsdDescriptorValue {
  /// Four-character OSType stored before this value.
  String get type;
}

/// A one-byte descriptor Boolean.
final class PsdBooleanValue extends PsdDescriptorValue {
  /// Boolean payload.
  final bool value;

  /// Creates a Boolean descriptor value.
  PsdBooleanValue(this.value);

  @override
  String get type => 'bool';
}

/// A signed 32-bit descriptor integer.
final class PsdIntegerValue extends PsdDescriptorValue {
  /// Integer payload.
  final int value;

  /// Creates an integer descriptor value.
  PsdIntegerValue(this.value);

  @override
  String get type => 'long';
}

/// A signed 64-bit descriptor integer.
final class PsdLargeIntegerValue extends PsdDescriptorValue {
  /// Integer payload.
  final int value;

  /// Creates a large-integer descriptor value.
  PsdLargeIntegerValue(this.value);

  @override
  String get type => 'comp';
}

/// A double-precision descriptor number.
final class PsdDoubleValue extends PsdDescriptorValue {
  /// Numeric payload.
  final double value;

  /// Creates a double descriptor value.
  PsdDoubleValue(this.value);

  @override
  String get type => 'doub';
}

/// A double-precision number carrying a Photoshop unit code.
final class PsdUnitFloatValue extends PsdDescriptorValue {
  /// Four-character unit such as `#Pxl` or `#Pnt`.
  final String unit;

  /// Numeric payload expressed in [unit].
  final double value;

  /// Creates a unit-float descriptor value.
  PsdUnitFloatValue({required this.unit, required this.value});

  @override
  String get type => 'UntF';
}

/// A list of double-precision values sharing a Photoshop unit code.
final class PsdUnitFloatsValue extends PsdDescriptorValue {
  /// Four-character unit such as `#Pxl` or `#Pnt`.
  final String unit;

  /// Numeric payloads expressed in [unit].
  final List<double> values;

  /// Creates a unit-floats descriptor value.
  PsdUnitFloatsValue({required this.unit, required this.values});

  @override
  String get type => 'UnFl';
}

/// A UTF-16 Photoshop descriptor string.
final class PsdStringValue extends PsdDescriptorValue {
  /// String payload.
  final String value;

  /// Creates a string descriptor value.
  PsdStringValue(this.value);

  @override
  String get type => 'TEXT';
}

/// A pair of Photoshop type and enumeration identifiers.
final class PsdEnumeratedValue extends PsdDescriptorValue {
  /// Enumeration type identifier.
  final String typeId;

  /// Selected enumeration identifier.
  final String value;

  /// Whether [typeId] used the compact zero-length representation.
  final bool _compactTypeId;

  /// Whether [value] used the compact zero-length representation.
  final bool _compactValue;

  /// Creates an enumerated descriptor value.
  PsdEnumeratedValue({required this.typeId, required this.value, this._compactTypeId = true, this._compactValue = true});

  @override
  String get type => 'enum';
}

/// A nested action descriptor.
final class PsdObjectValue extends PsdDescriptorValue {
  /// Nested descriptor payload.
  final PsdDescriptor value;

  /// Whether this uses the global-object OSType.
  final bool global;

  /// Creates a nested descriptor value.
  PsdObjectValue(this.value, {this.global = false});

  @override
  String get type => global ? 'GlbO' : 'Objc';
}

/// A descriptor-shaped object array with an explicit element count.
final class PsdObjectArrayValue extends PsdDescriptorValue {
  /// Number of logical array elements described by [value].
  final int itemsCount;

  /// Descriptor containing the array's column-oriented values.
  final PsdDescriptor value;

  /// Creates an object-array descriptor value.
  PsdObjectArrayValue({required this.itemsCount, required this.value});

  @override
  String get type => 'ObAr';
}

/// An ordered list of independently typed descriptor values.
final class PsdListValue extends PsdDescriptorValue {
  /// Ordered list payload.
  final List<PsdDescriptorValue> values;

  /// Creates a descriptor list.
  PsdListValue(this.values);

  @override
  String get type => 'VlLs';
}

/// Opaque length-prefixed descriptor data.
final class PsdRawValue extends PsdDescriptorValue {
  /// Opaque bytes.
  final Uint8List value;

  /// Creates a raw-data descriptor value.
  PsdRawValue(this.value);

  @override
  String get type => 'tdta';
}

/// Opaque length-prefixed platform alias data.
final class PsdAliasValue extends PsdDescriptorValue {
  /// Opaque alias bytes.
  final Uint8List value;

  /// Creates an alias descriptor value.
  PsdAliasValue(this.value);

  @override
  String get type => 'alis';
}

/// A Photoshop class name and identifier.
final class PsdClassValue extends PsdDescriptorValue {
  /// Human-readable class name.
  final String name;

  /// Photoshop class identifier.
  final String classId;

  /// Whether this uses the global-class OSType.
  final bool global;

  /// Whether [classId] used the compact zero-length representation.
  final bool _compactClassId;

  /// Creates a class descriptor value.
  PsdClassValue({required this.name, required this.classId, this.global = false, this._compactClassId = true});

  @override
  String get type => global ? 'GlbC' : 'type';
}

/// Encodes and decodes Photoshop action descriptors.
abstract final class PsdDescriptorCodec {
  /// Decodes one descriptor and requires all [bytes] to belong to it.
  static PsdDescriptor decode(Uint8List bytes) {
    final ({PsdDescriptor descriptor, int bytesRead}) decoded = decodePrefix(bytes);
    if (decoded.bytesRead != bytes.length) {
      throw PsdFormatException('Unexpected bytes after action descriptor', bytes, decoded.bytesRead);
    }
    return decoded.descriptor;
  }

  /// Decodes one descriptor from the beginning of [bytes].
  static ({PsdDescriptor descriptor, int bytesRead}) decodePrefix(Uint8List bytes) {
    final PsdBinaryReader reader = PsdBinaryReader(bytes);
    final PsdDescriptor descriptor = _readDescriptor(reader);
    return (descriptor: descriptor, bytesRead: reader.offset);
  }

  /// Encodes [descriptor] without an outer version or length field.
  static Uint8List encode(PsdDescriptor descriptor) {
    final PsdBinaryWriter writer = PsdBinaryWriter();
    _writeDescriptor(writer, descriptor);
    return writer.takeBytes();
  }
}

/// Reads one action descriptor from [reader].
PsdDescriptor _readDescriptor(PsdBinaryReader reader) {
  final String name = _readUnicodeString(reader);
  final ({String value, bool compact}) classId = _readId(reader);
  final int count = reader.readUint32();
  final List<PsdDescriptorItem> items = <PsdDescriptorItem>[];
  for (int index = 0; index < count; index++) {
    final ({String value, bool compact}) key = _readId(reader);
    final String type = reader.readString(4);
    items.add(PsdDescriptorItem(key: key.value, value: _readValue(reader, type), compactKey: key.compact));
  }
  return PsdDescriptor(name: name, classId: classId.value, items: items, compactClassId: classId.compact);
}

/// Reads a descriptor value whose OSType is [type].
PsdDescriptorValue _readValue(PsdBinaryReader reader, String type) => switch (type) {
  'bool' => PsdBooleanValue(reader.readUint8() != 0),
  'long' => PsdIntegerValue(reader.readInt32()),
  'comp' => PsdLargeIntegerValue(reader.readInt64()),
  'doub' => PsdDoubleValue(reader.readFloat64()),
  'UntF' => PsdUnitFloatValue(unit: reader.readString(4), value: reader.readFloat64()),
  'UnFl' => PsdUnitFloatsValue(
    unit: reader.readString(4),
    values: <double>[for (int index = 0, count = reader.readUint32(); index < count; index++) reader.readFloat64()],
  ),
  'TEXT' => PsdStringValue(_readUnicodeString(reader)),
  'enum' => _readEnumeratedValue(reader),
  'Objc' => PsdObjectValue(_readDescriptor(reader)),
  'GlbO' => PsdObjectValue(_readDescriptor(reader), global: true),
  'ObAr' => PsdObjectArrayValue(itemsCount: reader.readUint32(), value: _readDescriptor(reader)),
  'VlLs' => PsdListValue(<PsdDescriptorValue>[
    for (int index = 0, count = reader.readUint32(); index < count; index++) _readValue(reader, reader.readString(4)),
  ]),
  'tdta' => PsdRawValue(reader.readBytes(reader.readLength(wide: false, label: 'descriptor raw data'))),
  'alis' => PsdAliasValue(reader.readBytes(reader.readLength(wide: false, label: 'descriptor alias'))),
  'type' => _readClassValue(reader, global: false),
  'GlbC' => _readClassValue(reader, global: true),
  _ => throw PsdFormatException('Unsupported action-descriptor type "$type"', reader.bytes, reader.baseOffset + reader.offset - 4),
};

/// Writes [descriptor] without an outer version or length field.
void _writeDescriptor(PsdBinaryWriter writer, PsdDescriptor descriptor) {
  _writeUnicodeString(writer, descriptor.name);
  _writeId(writer, descriptor.classId, compact: descriptor._compactClassId);
  writer.writeUint32(descriptor.items.length);
  for (final PsdDescriptorItem item in descriptor.items) {
    _writeId(writer, item.key, compact: item._compactKey);
    writer.writeString(item.value.type);
    _writeValue(writer, item.value);
  }
}

/// Writes one typed descriptor [value].
void _writeValue(PsdBinaryWriter writer, PsdDescriptorValue value) {
  switch (value) {
    case PsdBooleanValue():
      writer.writeUint8(value.value ? 1 : 0);
    case PsdIntegerValue():
      writer.writeInt32(value.value);
    case PsdLargeIntegerValue():
      writer.writeInt64(value.value);
    case PsdDoubleValue():
      writer.writeFloat64(value.value);
    case PsdUnitFloatValue():
      _writeFourCharacters(writer, value.unit, 'descriptor unit');
      writer.writeFloat64(value.value);
    case PsdUnitFloatsValue():
      _writeFourCharacters(writer, value.unit, 'descriptor unit');
      writer.writeUint32(value.values.length);
      value.values.forEach(writer.writeFloat64);
    case PsdStringValue():
      _writeUnicodeString(writer, value.value);
    case PsdEnumeratedValue():
      _writeId(writer, value.typeId, compact: value._compactTypeId);
      _writeId(writer, value.value, compact: value._compactValue);
    case PsdObjectValue():
      _writeDescriptor(writer, value.value);
    case PsdObjectArrayValue():
      writer.writeUint32(value.itemsCount);
      _writeDescriptor(writer, value.value);
    case PsdListValue():
      writer.writeUint32(value.values.length);
      for (final PsdDescriptorValue item in value.values) {
        writer.writeString(item.type);
        _writeValue(writer, item);
      }
    case PsdRawValue():
      writer
        ..writeUint32(value.value.length)
        ..writeBytes(value.value);
    case PsdAliasValue():
      writer
        ..writeUint32(value.value.length)
        ..writeBytes(value.value);
    case PsdClassValue():
      _writeUnicodeString(writer, value.name);
      _writeId(writer, value.classId, compact: value._compactClassId);
  }
}

/// Reads a length-prefixed big-endian UTF-16 string.
String _readUnicodeString(PsdBinaryReader reader) {
  final int length = reader.readUint32();
  if (length > reader.remaining ~/ 2) {
    throw const PsdFormatException('Truncated descriptor Unicode string');
  }
  return String.fromCharCodes(<int>[for (int index = 0; index < length; index++) reader.readUint16()]);
}

/// Writes [value] as a length-prefixed big-endian UTF-16 string.
void _writeUnicodeString(PsdBinaryWriter writer, String value) {
  writer.writeUint32(value.codeUnits.length);
  value.codeUnits.forEach(writer.writeUint16);
}

/// Reads a variable-length Photoshop identifier.
({String value, bool compact}) _readId(PsdBinaryReader reader) {
  final int length = reader.readUint32();
  return (value: reader.readString(length == 0 ? 4 : length), compact: length == 0);
}

/// Writes a four-byte or length-prefixed Photoshop identifier.
void _writeId(PsdBinaryWriter writer, String value, {required bool compact}) {
  if (compact && value.length == 4 && value.codeUnits.every((unit) => unit <= 0xff)) {
    writer
      ..writeUint32(0)
      ..writeString(value);
    return;
  }
  if (value.codeUnits.any((unit) => unit > 0xff)) {
    throw const PsdWriteException('Descriptor identifiers must contain one-byte characters');
  }
  writer
    ..writeUint32(value.length)
    ..writeString(value);
}

/// Reads both identifiers in an enumerated descriptor value.
PsdEnumeratedValue _readEnumeratedValue(PsdBinaryReader reader) {
  final ({String value, bool compact}) typeId = _readId(reader);
  final ({String value, bool compact}) value = _readId(reader);
  return PsdEnumeratedValue(
    typeId: typeId.value,
    value: value.value,
    compactTypeId: typeId.compact,
    compactValue: value.compact,
  );
}

/// Reads a class descriptor value and its identifier representation.
PsdClassValue _readClassValue(PsdBinaryReader reader, {required bool global}) {
  final String name = _readUnicodeString(reader);
  final ({String value, bool compact}) classId = _readId(reader);
  return PsdClassValue(name: name, classId: classId.value, global: global, compactClassId: classId.compact);
}

/// Writes a required four-character descriptor code.
void _writeFourCharacters(PsdBinaryWriter writer, String value, String label) {
  if (value.length != 4 || value.codeUnits.any((unit) => unit > 0xff)) {
    throw PsdWriteException('$label must contain four one-byte characters');
  }
  writer.writeString(value);
}
