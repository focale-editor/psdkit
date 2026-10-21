part of '../codec.dart';

/// Writes the fixed 26-byte document header shared by both output modes.
void _writeDocumentHeader(PsBinaryWriter writer, PsdDocument document, PsdVersion version) {
  writer
    ..writeString('8BPS')
    ..writeUint16(version.code)
    ..writeZeros(6)
    ..writeUint16(document.channels)
    ..writeUint32(document.height)
    ..writeUint32(document.width)
    ..writeUint16(document.depth)
    ..writeUint16(document.colorMode.code);
}

/// Writes a validated resource header without copying its payload.
void _writeImageResourceHeader(PsBinaryWriter writer, PsdImageResource resource) {
  _requireFourCharacters(resource.signature, 'image-resource signature');
  if (resource.id < 0 || resource.id > 0xffff) {
    throw PsWriteException(message: 'Image resource id ${resource.id} is outside 0...65535');
  }
  final Uint8List name = _legacyName(resource.name);
  writer
    ..writeString(resource.signature)
    ..writeUint16(resource.id)
    ..writeUint8(name.length)
    ..writeBytes(name);
  if ((name.length + 1).isOdd) {
    writer.writeUint8(0);
  }
  writer.writeUint32(resource.data.length);
}

/// Writes validated layer metadata following its channel length records.
void _writeLayerRecordMetadata(PsBinaryWriter writer, PsdLayer layer, PsdVersion version) {
  _requireFourCharacters(layer.blendMode, 'blend mode');
  if (layer.opacity < 0 || layer.opacity > 255 || layer.clipping < 0 || layer.clipping > 255 || layer.flags < 0 || layer.flags > 255) {
    throw const PsWriteException(message: 'Layer opacity, clipping, and flags must fit in one byte');
  }
  final Uint8List extra = _writeLayerExtra(layer, version);
  writer
    ..writeString('8BIM')
    ..writeString(layer.blendMode)
    ..writeUint8(layer.opacity)
    ..writeUint8(layer.clipping)
    ..writeUint8(layer.flags)
    ..writeUint8(0)
    ..writeUint32(extra.length)
    ..writeBytes(extra);
}
