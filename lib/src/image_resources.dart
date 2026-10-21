import 'dart:convert';
import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:psdkit/src/model.dart';
import 'package:psdkit/src/paths.dart';

part 'image_resources/binary_io.dart';
part 'image_resources/decoder.dart';
part 'image_resources/document_info.dart';
part 'image_resources/encoder.dart';
part 'image_resources/identifiers.dart';
part 'image_resources/print_settings.dart';
part 'image_resources/values.dart';

/// Encodes and decodes semantic Photoshop image-resource payloads.
abstract final class PsdImageResourceCodec {
  /// Decodes [data] according to [resourceId].
  static PsdImageResourceData decode(Uint8List data, {required int resourceId}) {
    final PsBinaryReader reader = PsBinaryReader(bytes: data);
    final PsdImageResourceData decoded = _readImageResource(reader, resourceId);
    if (!reader.isAtEnd) {
      throw PsFormatException(message: 'Unexpected bytes after image resource $resourceId', source: data, offset: reader.offset);
    }
    return decoded;
  }

  /// Decodes supported data and returns an opaque value for unknown or malformed resources.
  static PsdImageResourceData tryDecode(Uint8List data, {required int resourceId}) {
    try {
      return decode(data, resourceId: resourceId);
    } on Object {
      return PsdRawImageResource(resourceId: resourceId, data: data);
    }
  }

  /// Encodes one semantic or opaque resource payload.
  static Uint8List encode(PsdImageResourceData value) {
    final PsBinaryWriter writer = PsBinaryWriter();
    _writeImageResource(writer, value);
    return writer.takeBytes();
  }
}

/// Convenient semantic access and replacement on a resource block.
extension PsdImageResourceDecoding on PsdImageResource {
  /// Decoded resource value, falling back to [PsdRawImageResource].
  PsdImageResourceData get decoded => PsdImageResourceCodec.tryDecode(data, resourceId: id);

  /// Returns a block whose payload is encoded from [value].
  PsdImageResource withDecoded(PsdImageResourceData value) {
    if (value.resourceId != id) {
      throw PsWriteException(message: 'Resource value ${value.resourceId} cannot replace block $id');
    }
    return PsdImageResource(id: id, name: name, signature: signature, data: PsdImageResourceCodec.encode(value));
  }
}

/// Convenient semantic access and replacement on complete documents.
extension PsdDocumentImageResources on PsdDocument {
  /// Returns the last resource block matching [id].
  PsdImageResource? imageResource(int id) {
    for (final PsdImageResource resource in imageResources.reversed) {
      if (resource.id == id) {
        return resource;
      }
    }
    return null;
  }

  /// Returns the last decoded resource value matching [id].
  PsdImageResourceData? decodedImageResource(int id) => imageResource(id)?.decoded;

  /// Returns a document where all blocks matching `value.resourceId` are replaced once.
  PsdDocument withImageResourceData(PsdImageResourceData value, {String name = '', String signature = '8BIM'}) {
    final List<PsdImageResource> resources = <PsdImageResource>[];
    bool replaced = false;
    for (final PsdImageResource resource in imageResources) {
      if (resource.id == value.resourceId) {
        if (!replaced) {
          resources.add(resource.withDecoded(value));
          replaced = true;
        }
      } else {
        resources.add(resource);
      }
    }
    if (!replaced) {
      resources.add(PsdImageResource(id: value.resourceId, name: name, signature: signature, data: PsdImageResourceCodec.encode(value)));
    }
    return _copyDocumentWithImageResources(this, resources);
  }

  /// Returns a document without resources matching [id].
  PsdDocument withoutImageResource(int id) => _copyDocumentWithImageResources(
    this,
    <PsdImageResource>[
      for (final PsdImageResource resource in imageResources)
        if (resource.id != id) resource,
    ],
  );
}

/// Copies [document] while replacing only its image-resource list.
PsdDocument _copyDocumentWithImageResources(PsdDocument document, List<PsdImageResource> resources) => PsdDocument(
  version: document.version,
  width: document.width,
  height: document.height,
  channels: document.channels,
  depth: document.depth,
  colorMode: document.colorMode,
  colorModeData: document.colorModeData,
  imageResources: resources,
  layers: document.layers,
  mergedImage: document.mergedImage,
  mergedImageCompression: document.mergedImageCompression,
  mergedTransparency: document.mergedTransparency,
  globalLayerMaskData: document.globalLayerMaskData,
  additionalLayerInfo: document.additionalLayerInfo,
);
