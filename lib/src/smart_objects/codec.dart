part of '../smart_objects.dart';

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
PsdVersionedDescriptor _readVersionedDescriptor(PsBinaryReader reader) => PsVersionedDescriptorCodec.read(reader);

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
  PsVersionedDescriptorCodec.write(writer, value);
}
