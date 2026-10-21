import 'dart:typed_data';

import 'package:pscore/pscore.dart';

part 'smart_objects/binary_io.dart';
part 'smart_objects/codec.dart';
part 'smart_objects/linked_resource.dart';
part 'smart_objects/placed_layer.dart';
part 'smart_objects/smart_filters.dart';

/// Keys used by modern and legacy Photoshop smart-object layer blocks.
const Set<String> psdSmartObjectLayerKeys = <String>{'SoLd', 'SoLE', 'plLd'};

/// Keys used by Photoshop linked-resource blocks at document level.
const Set<String> psdLinkedResourceKeys = <String>{'lnkD', 'lnk2', 'lnk3'};

/// Identifies the content storage strategy of a linked Photoshop resource.
enum PsdLinkedResourceType {
  /// File bytes are embedded in the PSD or PSB.
  embedded(code: 'liFD'),

  /// The content resides in an external file.
  external(code: 'liFE'),

  /// A historical platform alias identifies the content.
  alias(code: 'liFA');

  /// Four-character value stored in the linked-resource entry.
  final String code;

  /// Creates a resource type from its stored [code].
  const PsdLinkedResourceType({required this.code});
}

/// Backward-compatible name for a shared versioned Action Descriptor.
typedef PsdVersionedDescriptor = PsVersionedDescriptor;

/// Encodes and decodes smart-object layer metadata.
abstract final class PsdSmartObjectCodec {
  /// Decodes one smart-object layer [data] selected by [key].
  static PsdSmartObjectLayerData decode(Uint8List data, {required String key}) {
    if (!psdSmartObjectLayerKeys.contains(key)) {
      throw PsFormatException(message: 'Unsupported smart-object key "$key"', source: data, offset: 0);
    }
    try {
      final PsBinaryReader reader = PsBinaryReader(bytes: data);
      return key == 'plLd' ? _readLegacyPlacedLayer(reader) : _readDescriptorSmartObject(reader, key);
    } on FormatException {
      return PsdRawSmartObject(blockKey: key, data: data);
    }
  }

  /// Attempts to decode a smart-object block.
  static PsdSmartObjectLayerData? tryDecode(Uint8List data, {required String key}) {
    try {
      return decode(data, key: key);
    } on Object {
      return null;
    }
  }

  /// Encodes one smart-object layer [value].
  static Uint8List encode(PsdSmartObjectLayerData value) {
    final PsBinaryWriter writer = PsBinaryWriter();
    switch (value) {
      case PsdDescriptorSmartObject():
        _writeFourCharacters(writer, value.identifier, 'smart-object identifier');
        writer.writeUint32(value.version);
        if (value.blockKey == 'SoLd') {
          writer.writeUint32(value.descriptorVersion ?? 16);
        } else if (value.descriptorVersion != null) {
          throw const PsWriteException(message: 'SoLE smart objects do not store a descriptor-version field');
        }
        writer
          ..writeBytes(PsDescriptorCodec.encode(value.descriptor))
          ..writeBytes(value.trailingData);
      case PsdLegacyPlacedLayer():
        _writeLegacyPlacedLayer(writer, value);
      case PsdRawSmartObject():
        writer.writeBytes(value.data);
    }
    return writer.takeBytes();
  }
}

/// Encodes and decodes document-level linked-resource blocks.
abstract final class PsdLinkedResourceCodec {
  /// Decodes one entry body without its outer 64-bit length.
  static PsdLinkedResource decodeEntry(Uint8List data) => _readLinkedResource(PsBinaryReader(bytes: data));

  /// Decodes every complete length-prefixed entry in [data].
  static PsdLinkedResourceBlock decode(Uint8List data, {String key = 'lnk2'}) {
    if (!psdLinkedResourceKeys.contains(key)) {
      throw PsFormatException(message: 'Unsupported linked-resource key "$key"', source: data, offset: 0);
    }
    final PsBinaryReader reader = PsBinaryReader(bytes: data);
    final List<PsdLinkedResourceEntry> entries = <PsdLinkedResourceEntry>[];
    while (reader.remaining >= 8) {
      final int length = reader.readUint64();
      if (length > reader.remaining) {
        throw PsFormatException(message: 'Linked-resource entry length $length exceeds ${reader.remaining} bytes', source: data, offset: reader.offset);
      }
      final PsBinaryReader entry = _readView(reader, length);
      final Uint8List padding = reader.readBytes(_entryPaddingLength(length));
      try {
        entries.add(_readLinkedResource(entry, entryPadding: padding));
      } on Object {
        entries.add(PsdRawLinkedResource(data: entry.bytes, entryPadding: padding));
      }
    }
    return PsdLinkedResourceBlock(blockKey: key, entries: entries, trailingData: reader.readBytes(reader.remaining));
  }

  /// Attempts to decode a linked-resource block.
  static PsdLinkedResourceBlock? tryDecode(Uint8List data, {String key = 'lnk2'}) {
    try {
      return decode(data, key: key);
    } on Object {
      return null;
    }
  }

  /// Encodes a complete linked-resource [block].
  static Uint8List encode(PsdLinkedResourceBlock block) {
    final PsBinaryWriter writer = PsBinaryWriter();
    for (final PsdLinkedResourceEntry entry in block.entries) {
      final Uint8List data = switch (entry) {
        PsdLinkedResource() => _writeLinkedResource(entry),
        PsdRawLinkedResource() => entry.data,
      };
      writer
        ..writeUint64(data.length)
        ..writeBytes(data);
      final int paddingLength = _entryPaddingLength(data.length);
      if (entry.entryPadding.isNotEmpty && entry.entryPadding.length != paddingLength) {
        throw PsWriteException(message: 'Linked-resource entry requires $paddingLength padding bytes, received ${entry.entryPadding.length}');
      }
      writer.writeBytes(entry.entryPadding.isEmpty ? Uint8List(paddingLength) : entry.entryPadding);
    }
    writer.writeBytes(block.trailingData);
    return writer.takeBytes();
  }
}
