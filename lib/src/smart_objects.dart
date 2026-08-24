import 'dart:typed_data';

import 'package:pscore/pscore.dart';

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

/// A descriptor preceded by its Photoshop descriptor version.
final class PsdVersionedDescriptor {
  /// Descriptor format version, normally 16.
  final int version;

  /// Complete action descriptor.
  final PsDescriptor descriptor;

  /// Creates a versioned action descriptor.
  const PsdVersionedDescriptor({this.version = 16, required this.descriptor});
}

/// Eight transform coordinates ordered by the four placed-image corners.
final class PsdPlacedTransform {
  /// Top-left horizontal coordinate.
  final double topLeftX;

  /// Top-left vertical coordinate.
  final double topLeftY;

  /// Top-right horizontal coordinate.
  final double topRightX;

  /// Top-right vertical coordinate.
  final double topRightY;

  /// Bottom-right horizontal coordinate.
  final double bottomRightX;

  /// Bottom-right vertical coordinate.
  final double bottomRightY;

  /// Bottom-left horizontal coordinate.
  final double bottomLeftX;

  /// Bottom-left vertical coordinate.
  final double bottomLeftY;

  /// Creates four-corner placed-image coordinates.
  const PsdPlacedTransform({
    required this.topLeftX,
    required this.topLeftY,
    required this.topRightX,
    required this.topRightY,
    required this.bottomRightX,
    required this.bottomRightY,
    required this.bottomLeftX,
    required this.bottomLeftY,
  });

  /// Creates transform coordinates from the eight stored [values].
  factory PsdPlacedTransform.fromList({required List<double> values}) {
    if (values.length != 8) {
      throw ArgumentError.value(values.length, 'values.length', 'must be eight');
    }
    return PsdPlacedTransform(
      topLeftX: values[0],
      topLeftY: values[1],
      topRightX: values[2],
      topRightY: values[3],
      bottomRightX: values[4],
      bottomRightY: values[5],
      bottomLeftX: values[6],
      bottomLeftY: values[7],
    );
  }

  /// Returns the eight coordinates in Photoshop storage order.
  List<double> toList() => <double>[
    topLeftX,
    topLeftY,
    topRightX,
    topRightY,
    bottomRightX,
    bottomRightY,
    bottomLeftX,
    bottomLeftY,
  ];
}

/// Base type for modern, legacy, and opaque smart-object layer data.
sealed class PsdSmartObjectLayerData {
  /// Creates a smart-object layer-data base value.
  const PsdSmartObjectLayerData();

  /// Four-character additional-layer-information key.
  String get blockKey;

  /// Identifier used to find the corresponding linked resource, when known.
  String? get linkedResourceId;

  /// Four-corner transform, when the format exposes one.
  PsdPlacedTransform? get transform;
}

/// Modern descriptor-backed smart-object data from `SoLd` or `SoLE`.
final class PsdDescriptorSmartObject extends PsdSmartObjectLayerData {
  /// Four-character block key, normally `SoLd` or `SoLE`.
  @override
  final String blockKey;

  /// Header identifier, normally `soLD`.
  final String identifier;

  /// Smart-object structure version.
  final int version;

  /// Descriptor version when stored explicitly by the block.
  final int? descriptorVersion;

  /// Complete editable placed-layer descriptor.
  final PsDescriptor descriptor;

  /// Uninterpreted bytes following the descriptor.
  final Uint8List trailingData;

  /// Creates modern smart-object layer data.
  PsdDescriptorSmartObject({
    this.blockKey = 'SoLd',
    this.identifier = 'soLD',
    this.version = 4,
    int? descriptorVersion,
    required this.descriptor,
    Uint8List? trailingData,
  }) : descriptorVersion = descriptorVersion ?? (blockKey == 'SoLd' ? 16 : null),
       trailingData = trailingData ?? Uint8List(0) {
    if (blockKey != 'SoLd' && blockKey != 'SoLE') {
      throw ArgumentError.value(blockKey, 'blockKey', 'must be SoLd or SoLE');
    }
  }

  @override
  String? get linkedResourceId {
    final PsDescriptorValue? value = descriptor.value('Idnt');
    if (value is! PsStringValue) {
      return null;
    }
    return value.value.endsWith('\u0000') ? value.value.substring(0, value.value.length - 1) : value.value;
  }

  @override
  PsdPlacedTransform? get transform => _transformFromValue(descriptor.value('Trnf'));

  /// Optional non-affine four-corner transform.
  PsdPlacedTransform? get nonAffineTransform => _transformFromValue(descriptor.value('nonAffineTransform'));

  /// Returns a copy whose descriptor property [key] is [value].
  PsdDescriptorSmartObject withProperty(String key, PsDescriptorValue value) => PsdDescriptorSmartObject(
    blockKey: blockKey,
    identifier: identifier,
    version: version,
    descriptorVersion: descriptorVersion,
    descriptor: descriptor.withValue(key, value),
    trailingData: trailingData,
  );

  /// Returns a copy linked to [resourceId].
  PsdDescriptorSmartObject withLinkedResourceId(String resourceId) {
    final PsDescriptorValue? current = descriptor.value('Idnt');
    final bool terminalNull = current is PsStringValue && current.value.endsWith('\u0000');
    return withProperty('Idnt', PsStringValue(value: '$resourceId${terminalNull ? '\u0000' : ''}'));
  }

  /// Returns a copy whose affine corner transform is [value].
  PsdDescriptorSmartObject withTransform(PsdPlacedTransform value) => withProperty(
    'Trnf',
    PsListValue(values: <PsDescriptorValue>[for (final double coordinate in value.toList()) PsDoubleValue(value: coordinate)]),
  );
}

/// Historical `plLd` placed-layer data used before Photoshop CS3.
final class PsdLegacyPlacedLayer extends PsdSmartObjectLayerData {
  /// Header type, normally `plcL`.
  final String typeCode;

  /// Legacy structure version, normally 3.
  final int version;

  /// Pascal-string linked-resource identifier.
  final String id;

  /// Exact padding that followed the Pascal identifier.
  final Uint8List idPadding;

  /// Selected page number.
  final int pageNumber;

  /// Total page count.
  final int totalPages;

  /// Historical anti-alias policy value.
  final int antiAliasPolicy;

  /// Placed-layer type: unknown, vector, raster, or image stack.
  final int placedType;

  /// Four-corner transformation.
  @override
  final PsdPlacedTransform transform;

  /// Warp structure version.
  final int warpVersion;

  /// Complete versioned warp descriptor.
  final PsdVersionedDescriptor warp;

  /// Uninterpreted bytes following the warp descriptor.
  final Uint8List trailingData;

  /// Creates historical placed-layer data.
  PsdLegacyPlacedLayer({
    this.typeCode = 'plcL',
    this.version = 3,
    required this.id,
    Uint8List? idPadding,
    this.pageNumber = 1,
    this.totalPages = 1,
    this.antiAliasPolicy = 0,
    this.placedType = 0,
    required this.transform,
    this.warpVersion = 0,
    required this.warp,
    Uint8List? trailingData,
  }) : idPadding = idPadding ?? Uint8List(0),
       trailingData = trailingData ?? Uint8List(0);

  @override
  String get blockKey => 'plLd';

  @override
  String get linkedResourceId => id;
}

/// Loss-preserving smart-object data whose structure could not be decoded.
final class PsdRawSmartObject extends PsdSmartObjectLayerData {
  /// Four-character block key.
  @override
  final String blockKey;

  /// Exact block payload.
  final Uint8List data;

  /// Creates an opaque smart-object layer block.
  const PsdRawSmartObject({required this.blockKey, required this.data});

  @override
  String? get linkedResourceId => null;

  @override
  PsdPlacedTransform? get transform => null;
}

/// One calendar timestamp stored by an external linked resource.
final class PsdLinkedResourceTimestamp {
  /// Four-digit year.
  final int year;

  /// Month from 1 through 12.
  final int month;

  /// Day of month.
  final int day;

  /// Hour from 0 through 23.
  final int hour;

  /// Minute from 0 through 59.
  final int minute;

  /// Seconds, including a possible fractional part.
  final double seconds;

  /// Creates an exact linked-resource timestamp.
  const PsdLinkedResourceTimestamp({
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    required this.seconds,
  });

  /// Converts the timestamp to UTC when all components are accepted by Dart.
  DateTime? get utcDateTime {
    if (month < 1 || month > 12 || day < 1 || day > 31 || hour < 0 || hour > 23 || minute < 0 || minute > 59 || seconds < 0) {
      return null;
    }
    final int wholeSeconds = seconds.floor();
    final int microseconds = ((seconds - wholeSeconds) * Duration.microsecondsPerSecond).round();
    return DateTime.utc(year, month, day, hour, minute, wholeSeconds, 0, microseconds);
  }
}

/// Base type for one length-prefixed entry in a linked-resource block.
sealed class PsdLinkedResourceEntry {
  /// Creates a linked-resource entry base value.
  const PsdLinkedResourceEntry();

  /// Exact alignment bytes following the length-prefixed entry body.
  Uint8List get entryPadding;
}

/// An embedded, external, or alias-linked Photoshop file resource.
final class PsdLinkedResource extends PsdLinkedResourceEntry {
  /// Stored entry type.
  final PsdLinkedResourceType type;

  /// Linked-resource structure version from 1 through 7.
  final int version;

  /// Pascal-string resource identifier used by smart-object layers.
  final String id;

  /// Exact padding that followed the Pascal identifier.
  final Uint8List idPadding;

  /// Original file name without a terminal NUL.
  final String name;

  /// Whether the stored Unicode name ended in NUL.
  final bool nameHasTerminalNull;

  /// Four-character original file type.
  final String fileType;

  /// Four-character original file creator.
  final String fileCreator;

  /// Optional file-open descriptor.
  final PsdVersionedDescriptor? fileOpenDescriptor;

  /// Stored content-data length, retained for non-embedded variants.
  final int declaredDataLength;

  /// External-file location and metadata descriptor.
  final PsdVersionedDescriptor? linkedFileDescriptor;

  /// External-file modification timestamp.
  final PsdLinkedResourceTimestamp? timestamp;

  /// External file size in bytes.
  final int? externalFileSize;

  /// Historical alias bytes.
  final Uint8List aliasData;

  /// Complete embedded file bytes for `liFD` entries.
  final Uint8List? data;

  /// Child document identifier introduced in version 5.
  final String? childDocumentId;

  /// Whether the stored child document identifier ended in NUL.
  final bool childDocumentIdHasTerminalNull;

  /// Library asset modification time introduced in version 6.
  final double? assetModificationTime;

  /// Library asset lock flag introduced in version 7.
  final bool? assetLocked;

  /// Uninterpreted bytes remaining inside the length-prefixed entry.
  final Uint8List trailingData;

  /// Exact alignment bytes following the entry body.
  @override
  final Uint8List entryPadding;

  /// Creates one linked Photoshop file resource.
  PsdLinkedResource({
    required this.type,
    this.version = 7,
    required this.id,
    Uint8List? idPadding,
    required this.name,
    this.nameHasTerminalNull = true,
    this.fileType = '    ',
    this.fileCreator = '    ',
    this.fileOpenDescriptor,
    int? declaredDataLength,
    this.linkedFileDescriptor,
    this.timestamp,
    this.externalFileSize,
    Uint8List? aliasData,
    this.data,
    this.childDocumentId,
    this.childDocumentIdHasTerminalNull = true,
    this.assetModificationTime,
    this.assetLocked,
    Uint8List? trailingData,
    Uint8List? entryPadding,
  }) : declaredDataLength = declaredDataLength ?? data?.length ?? 0,
       idPadding = idPadding ?? Uint8List(0),
       aliasData = aliasData ?? Uint8List(0),
       trailingData = trailingData ?? Uint8List(0),
       entryPadding = entryPadding ?? Uint8List(0);

  /// Returns a copy whose embedded file bytes are [bytes].
  PsdLinkedResource withData(Uint8List bytes) => PsdLinkedResource(
    type: PsdLinkedResourceType.embedded,
    version: version,
    id: id,
    idPadding: idPadding,
    name: name,
    nameHasTerminalNull: nameHasTerminalNull,
    fileType: fileType,
    fileCreator: fileCreator,
    fileOpenDescriptor: fileOpenDescriptor,
    declaredDataLength: bytes.length,
    linkedFileDescriptor: null,
    data: bytes,
    childDocumentId: childDocumentId,
    childDocumentIdHasTerminalNull: childDocumentIdHasTerminalNull,
    assetModificationTime: assetModificationTime,
    assetLocked: assetLocked,
    trailingData: trailingData,
  );
}

/// One opaque linked-resource entry retained with its exact body.
final class PsdRawLinkedResource extends PsdLinkedResourceEntry {
  /// Exact bytes following the outer 64-bit length.
  final Uint8List data;

  /// Exact alignment bytes following the entry body.
  @override
  final Uint8List entryPadding;

  /// Creates an opaque linked-resource entry.
  const PsdRawLinkedResource({required this.data, required this.entryPadding});
}

/// A complete `lnkD`, `lnk2`, or `lnk3` document block.
final class PsdLinkedResourceBlock {
  /// Four-character tagged-block key.
  final String blockKey;

  /// Length-prefixed entries in file order.
  final List<PsdLinkedResourceEntry> entries;

  /// Uninterpreted bytes after the final complete entry.
  final Uint8List trailingData;

  /// Creates a linked-resource block.
  PsdLinkedResourceBlock({this.blockKey = 'lnk2', required this.entries, Uint8List? trailingData}) : trailingData = trailingData ?? Uint8List(0) {
    if (!psdLinkedResourceKeys.contains(blockKey)) {
      throw ArgumentError.value(blockKey, 'blockKey', 'must be lnkD, lnk2, or lnk3');
    }
  }

  /// All semantically decoded linked resources.
  List<PsdLinkedResource> get resources => <PsdLinkedResource>[
    for (final PsdLinkedResourceEntry entry in entries)
      if (entry is PsdLinkedResource) entry,
  ];
}

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
    } on PsFormatException {
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

/// Reads modern descriptor-backed smart-object data.
PsdDescriptorSmartObject _readDescriptorSmartObject(PsBinaryReader reader, String key) {
  final String identifier = reader.readString(4);
  final int version = reader.readUint32();
  final int? descriptorVersion = key == 'SoLd' ? reader.readUint32() : null;
  final Uint8List payload = reader.readBytes(reader.remaining);
  final ({PsDescriptor descriptor, int bytesRead}) decoded = PsDescriptorCodec.decodePrefix(payload);
  return PsdDescriptorSmartObject(
    blockKey: key,
    identifier: identifier,
    version: version,
    descriptorVersion: descriptorVersion,
    descriptor: decoded.descriptor,
    trailingData: Uint8List.fromList(Uint8List.sublistView(payload, decoded.bytesRead)),
  );
}

/// Reads historical fixed-field placed-layer data.
PsdLegacyPlacedLayer _readLegacyPlacedLayer(PsBinaryReader reader) {
  final String typeCode = reader.readString(4);
  final int version = reader.readUint32();
  final ({String value, Uint8List padding}) id = _readPascalString(reader, alignment: 1);
  final int pageNumber = reader.readUint32();
  final int totalPages = reader.readUint32();
  final int antiAliasPolicy = reader.readUint32();
  final int placedType = reader.readUint32();
  final PsdPlacedTransform transform = PsdPlacedTransform.fromList(
    values: <double>[for (int index = 0; index < 8; index++) reader.readFloat64()],
  );
  final int warpVersion = reader.readUint32();
  final int descriptorVersion = reader.readUint32();
  final Uint8List payload = reader.readBytes(reader.remaining);
  final ({PsDescriptor descriptor, int bytesRead}) decoded = PsDescriptorCodec.decodePrefix(payload);
  return PsdLegacyPlacedLayer(
    typeCode: typeCode,
    version: version,
    id: id.value,
    idPadding: id.padding,
    pageNumber: pageNumber,
    totalPages: totalPages,
    antiAliasPolicy: antiAliasPolicy,
    placedType: placedType,
    transform: transform,
    warpVersion: warpVersion,
    warp: PsdVersionedDescriptor(version: descriptorVersion, descriptor: decoded.descriptor),
    trailingData: Uint8List.fromList(Uint8List.sublistView(payload, decoded.bytesRead)),
  );
}

/// Reads one linked-resource entry body.
PsdLinkedResource _readLinkedResource(PsBinaryReader reader, {Uint8List? entryPadding}) {
  final String typeCode = reader.readString(4);
  final PsdLinkedResourceType type = PsdLinkedResourceType.values.firstWhere(
    (value) => value.code == typeCode,
    orElse: () => throw PsFormatException(message: 'Unknown linked-resource type "$typeCode"', source: reader.bytes, offset: 0),
  );
  final int version = reader.readUint32();
  if (version < 1 || version > 7) {
    throw PsFormatException(message: 'Unsupported linked-resource version $version', source: reader.bytes, offset: 4);
  }
  final ({String value, Uint8List padding}) id = _readPascalString(reader, alignment: 1);
  final ({String value, bool terminalNull}) name = _readUnicodeString(reader);
  final String fileType = reader.readString(4);
  final String fileCreator = reader.readString(4);
  final int dataLength = reader.readUint64();
  final PsdVersionedDescriptor? fileOpenDescriptor = reader.readUint8() == 0 ? null : _readVersionedDescriptor(reader);
  PsdVersionedDescriptor? linkedFileDescriptor;
  PsdLinkedResourceTimestamp? timestamp;
  int? externalFileSize;
  Uint8List aliasData = Uint8List(0);
  if (type == PsdLinkedResourceType.external) {
    linkedFileDescriptor = _readVersionedDescriptor(reader);
    if (version > 3) {
      timestamp = PsdLinkedResourceTimestamp(
        year: reader.readUint32(),
        month: reader.readUint8(),
        day: reader.readUint8(),
        hour: reader.readUint8(),
        minute: reader.readUint8(),
        seconds: reader.readFloat64(),
      );
    }
    externalFileSize = reader.readUint64();
  } else if (type == PsdLinkedResourceType.alias) {
    aliasData = reader.readBytes(8);
  }
  Uint8List? data;
  if (type == PsdLinkedResourceType.embedded) {
    data = _readByteView(reader, dataLength);
  }
  String? childDocumentId;
  bool childDocumentIdHasTerminalNull = true;
  if (version >= 5) {
    final ({String value, bool terminalNull}) child = _readUnicodeString(reader);
    childDocumentId = child.value;
    childDocumentIdHasTerminalNull = child.terminalNull;
  }
  final double? assetModificationTime = version >= 6 ? reader.readFloat64() : null;
  final bool? assetLocked = version >= 7 ? reader.readUint8() != 0 : null;
  return PsdLinkedResource(
    type: type,
    version: version,
    id: id.value,
    idPadding: id.padding,
    name: name.value,
    nameHasTerminalNull: name.terminalNull,
    fileType: fileType,
    fileCreator: fileCreator,
    fileOpenDescriptor: fileOpenDescriptor,
    declaredDataLength: dataLength,
    linkedFileDescriptor: linkedFileDescriptor,
    timestamp: timestamp,
    externalFileSize: externalFileSize,
    aliasData: aliasData,
    data: data,
    childDocumentId: childDocumentId,
    childDocumentIdHasTerminalNull: childDocumentIdHasTerminalNull,
    assetModificationTime: assetModificationTime,
    assetLocked: assetLocked,
    trailingData: reader.readBytes(reader.remaining),
    entryPadding: entryPadding,
  );
}

/// Reads a descriptor after its 32-bit version.
PsdVersionedDescriptor _readVersionedDescriptor(PsBinaryReader reader) {
  final int version = reader.readUint32();
  final ({PsDescriptor descriptor, int bytesRead}) decoded = PsDescriptorCodec.decodePrefix(
    Uint8List.sublistView(reader.bytes, reader.offset),
  );
  reader.skip(decoded.bytesRead);
  return PsdVersionedDescriptor(version: version, descriptor: decoded.descriptor);
}

/// Writes historical fixed-field placed-layer data.
void _writeLegacyPlacedLayer(PsBinaryWriter writer, PsdLegacyPlacedLayer value) {
  _writeFourCharacters(writer, value.typeCode, 'legacy placed-layer type');
  writer.writeUint32(value.version);
  _writePascalString(writer, value.id, value.idPadding, alignment: 1);
  writer
    ..writeUint32(value.pageNumber)
    ..writeUint32(value.totalPages)
    ..writeUint32(value.antiAliasPolicy)
    ..writeUint32(value.placedType);
  value.transform.toList().forEach(writer.writeFloat64);
  writer
    ..writeUint32(value.warpVersion)
    ..writeUint32(value.warp.version)
    ..writeBytes(PsDescriptorCodec.encode(value.warp.descriptor))
    ..writeBytes(value.trailingData);
}

/// Writes one semantic linked-resource entry body.
Uint8List _writeLinkedResource(PsdLinkedResource resource) {
  final PsBinaryWriter writer = PsBinaryWriter();
  _writeFourCharacters(writer, resource.type.code, 'linked-resource type');
  writer.writeUint32(resource.version);
  _writePascalString(writer, resource.id, resource.idPadding, alignment: 1);
  _writeUnicodeString(writer, resource.name, terminalNull: resource.nameHasTerminalNull);
  _writeFourCharacters(writer, resource.fileType, 'linked-resource file type');
  _writeFourCharacters(writer, resource.fileCreator, 'linked-resource file creator');
  final Uint8List embeddedData = resource.data ?? Uint8List(0);
  writer.writeUint64(resource.type == PsdLinkedResourceType.embedded ? embeddedData.length : resource.declaredDataLength);
  writer.writeUint8(resource.fileOpenDescriptor == null ? 0 : 1);
  if (resource.fileOpenDescriptor != null) {
    _writeVersionedDescriptor(writer, resource.fileOpenDescriptor!);
  }
  if (resource.type == PsdLinkedResourceType.external) {
    if (resource.linkedFileDescriptor == null) {
      throw const PsWriteException(message: 'External linked resources require a linked-file descriptor');
    }
    _writeVersionedDescriptor(writer, resource.linkedFileDescriptor!);
    if (resource.version > 3) {
      final PsdLinkedResourceTimestamp? timestamp = resource.timestamp;
      if (timestamp == null) {
        throw const PsWriteException(message: 'External linked-resource versions above 3 require a timestamp');
      }
      writer
        ..writeUint32(timestamp.year)
        ..writeUint8(timestamp.month)
        ..writeUint8(timestamp.day)
        ..writeUint8(timestamp.hour)
        ..writeUint8(timestamp.minute)
        ..writeFloat64(timestamp.seconds);
    }
    writer.writeUint64(resource.externalFileSize ?? 0);
  } else if (resource.type == PsdLinkedResourceType.alias) {
    if (resource.aliasData.length != 8) {
      throw const PsWriteException(message: 'Alias linked resources require exactly eight alias bytes');
    }
    writer.writeBytes(resource.aliasData);
  } else {
    writer.writeBytes(embeddedData);
  }
  if (resource.version >= 5) {
    _writeUnicodeString(
      writer,
      resource.childDocumentId ?? '',
      terminalNull: resource.childDocumentIdHasTerminalNull,
    );
  }
  if (resource.version >= 6) {
    writer.writeFloat64(resource.assetModificationTime ?? 0);
  }
  if (resource.version >= 7) {
    writer.writeUint8(resource.assetLocked == true ? 1 : 0);
  }
  writer.writeBytes(resource.trailingData);
  return writer.takeBytes();
}

/// Writes a descriptor preceded by its version.
void _writeVersionedDescriptor(PsBinaryWriter writer, PsdVersionedDescriptor value) {
  writer
    ..writeUint32(value.version)
    ..writeBytes(PsDescriptorCodec.encode(value.descriptor));
}

/// Converts a descriptor list of eight doubles to a placed transform.
PsdPlacedTransform? _transformFromValue(PsDescriptorValue? value) {
  if (value is! PsListValue || value.values.length != 8 || value.values.any((item) => item is! PsDoubleValue)) {
    return null;
  }
  return PsdPlacedTransform.fromList(
    values: <double>[for (final PsDescriptorValue item in value.values) (item as PsDoubleValue).value],
  );
}

/// Reads a one-byte-length Pascal string and exact alignment bytes.
({String value, Uint8List padding}) _readPascalString(PsBinaryReader reader, {required int alignment}) {
  final int length = reader.readUint8();
  final String value = reader.readString(length);
  return (value: value, padding: reader.readBytes(_pascalPaddingLength(length, alignment: alignment)));
}

/// Writes a Pascal [value] followed by its preserved [padding].
void _writePascalString(PsBinaryWriter writer, String value, Uint8List padding, {required int alignment}) {
  if (value.length > 255 || value.codeUnits.any((unit) => unit > 0xff)) {
    throw const PsWriteException(message: 'Pascal strings must contain at most 255 one-byte characters');
  }
  final int expectedPadding = _pascalPaddingLength(value.length, alignment: alignment);
  if (padding.length != expectedPadding) {
    throw PsWriteException(message: 'Pascal string requires $expectedPadding padding bytes, received ${padding.length}');
  }
  writer
    ..writeUint8(value.length)
    ..writeString(value)
    ..writeBytes(padding);
}

/// Returns padding required after a Pascal string of [length].
int _pascalPaddingLength(int length, {required int alignment}) => (alignment - ((length + 1) % alignment)) % alignment;

/// Returns the four-byte alignment padding after an entry body of [length].
int _entryPaddingLength(int length) => (4 - (length % 4)) % 4;

/// Reads a length-prefixed UTF-16 string and removes one terminal NUL.
({String value, bool terminalNull}) _readUnicodeString(PsBinaryReader reader) {
  final int count = reader.readUint32();
  if (count > reader.remaining ~/ 2) {
    throw PsFormatException(message: 'Truncated linked-resource Unicode string', source: reader.bytes, offset: reader.offset);
  }
  final List<int> units = <int>[for (int index = 0; index < count; index++) reader.readUint16()];
  final bool terminalNull = units.isNotEmpty && units.last == 0;
  return (value: String.fromCharCodes(terminalNull ? units.sublist(0, units.length - 1) : units), terminalNull: terminalNull);
}

/// Writes a length-prefixed UTF-16 [value].
void _writeUnicodeString(PsBinaryWriter writer, String value, {required bool terminalNull}) {
  writer.writeUint32(value.codeUnits.length + (terminalNull ? 1 : 0));
  value.codeUnits.forEach(writer.writeUint16);
  if (terminalNull) {
    writer.writeUint16(0);
  }
}

/// Creates a zero-copy bounded reader for the next [length] bytes.
PsBinaryReader _readView(PsBinaryReader reader, int length) {
  final Uint8List bytes = _readByteView(reader, length);
  return PsBinaryReader(bytes: bytes, baseOffset: reader.baseOffset + reader.offset - length);
}

/// Returns a zero-copy view of the next [length] bytes and advances [reader].
Uint8List _readByteView(PsBinaryReader reader, int length) {
  if (length < 0 || length > reader.remaining) {
    throw PsFormatException(message: 'Unexpected end of linked resource', source: reader.bytes, offset: reader.baseOffset + reader.offset);
  }
  final Uint8List bytes = Uint8List.sublistView(reader.bytes, reader.offset, reader.offset + length);
  reader.skip(length);
  return bytes;
}

/// Writes a required four-character one-byte code.
void _writeFourCharacters(PsBinaryWriter writer, String value, String label) {
  if (value.length != 4 || value.codeUnits.any((unit) => unit > 0xff)) {
    throw PsWriteException(message: '$label must contain four one-byte characters');
  }
  writer.writeString(value);
}
