part of '../codec.dart';

/// Photoshop layers and document metadata stored in TIFF tag 37724.
///
/// The TIFF raster supplies canvas dimensions, color mode and merged samples.
/// Use a raster codec such as Imcodec for that outer container.
final class PsdTiffData {
  /// PSD or PSB-sized embedded structures.
  final PsdVersion version;

  /// Original structure byte order, detected from block signatures.
  final Endian byteOrder;

  /// Sample depth advertised by the layer-info block key.
  final int depth;

  /// Editable layer records in Photoshop order.
  final List<PsdLayer> layers;

  /// Whether the layer count advertises merged transparency.
  final bool mergedTransparency;

  /// Global mask bytes normalized to PSD byte order.
  final Uint8List globalLayerMaskData;

  /// Global tagged blocks, with unknown Intel-order payloads explicitly marked.
  final List<PsdTaggedBlock> additionalLayerInfo;

  /// Opaque bytes following the last complete block.
  final Uint8List trailingData;

  /// Creates an editable Photoshop TIFF payload.
  PsdTiffData({
    required this.depth,
    required this.layers,
    this.version = PsdVersion.psd,
    this.byteOrder = Endian.big,
    this.mergedTransparency = false,
    Uint8List? globalLayerMaskData,
    this.additionalLayerInfo = const [],
    Uint8List? trailingData,
  }) : globalLayerMaskData = globalLayerMaskData ?? Uint8List(0),
       trailingData = trailingData ?? Uint8List(0);

  /// Extracts Photoshop metadata independently of the flattened TIFF raster.
  factory PsdTiffData.fromDocument(PsdDocument document) => PsdTiffData(
    depth: document.depth,
    layers: document.layers,
    version: document.version,
    mergedTransparency: document.mergedTransparency,
    globalLayerMaskData: document.globalLayerMaskData,
    additionalLayerInfo: document.additionalLayerInfo.where((block) => !const {'Layr', 'Lr16', 'Lr32'}.contains(block.key)).toList(growable: false),
  );

  /// Combines the private tags with canvas metadata and planar merged samples.
  PsdDocument toDocument({
    required int width,
    required int height,
    required int channels,
    required PsdColorMode colorMode,
    required List<Uint8List> mergedImage,
    List<PsdImageResource> imageResources = const [],
  }) => PsdDocument(
    width: width,
    height: height,
    channels: channels,
    depth: depth,
    colorMode: colorMode,
    mergedImage: mergedImage,
    version: version,
    layers: layers,
    mergedTransparency: mergedTransparency,
    globalLayerMaskData: globalLayerMaskData,
    additionalLayerInfo: additionalLayerInfo,
    imageResources: imageResources,
  );
}

/// Reads and writes Photoshop TIFF private-tag payloads in both byte orders.
abstract final class PsdTiffCodec {
  /// Standard Photoshop layer-data signature including its NUL terminator.
  static const String _signature = 'Adobe Photoshop Document Data Block\u0000';

  /// Wide-length Photoshop layer-data signature including its NUL terminator.
  static const String _wideSignature = 'Adobe Photoshop Document Data V0002\u0000';

  /// Decodes ImageSourceData (tag 37724), detecting its byte order independently.
  static PsdTiffData decode(Uint8List bytes, {int depth = 8, PsdReadOptions options = const PsdReadOptions()}) {
    final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
    final String signature = reader.readString(36);
    final PsdVersion version = switch (signature) {
      _signature => PsdVersion.psd,
      _wideSignature => PsdVersion.psb,
      _ => throw const PsFormatException(message: 'Invalid Photoshop ImageSourceData signature'),
    };
    final Uint8List body = reader.readBytes(reader.remaining);
    final Endian order = _order(body);
    final _PsdTiffTranscoder converter = _PsdTiffTranscoder(source: body, from: order, to: Endian.big, version: version);
    if (order != Endian.big) {
      converter.blocks();
    }
    final PsBinaryReader blocks = PsBinaryReader(bytes: order == Endian.big ? body : converter.output);
    _DecodedLayerInfo? layers;
    Uint8List mask = Uint8List(0);
    int sampleDepth = depth;
    final List<PsdTaggedBlock> global = [];
    final _PsdDecodeBudget budget = _PsdDecodeBudget(maximum: options.maxTotalDecodedBytes);
    while (blocks.remaining >= 12 && PsTaggedBlockCodec.hasSignature(blocks, signatures: _tiffSignatures)) {
      final PsTaggedBlockHeader header = PsTaggedBlockCodec.readHeader(
        blocks,
        signatures: _tiffSignatures,
        wideLengthResolver: (signature, key) => version == PsdVersion.psb && _widePsbTaggedBlocks.contains(key),
      );
      final Uint8List payload = blocks.readBytes(header.declaredLength);
      switch (header.key) {
        case 'Layr' || 'Lr16' || 'Lr32':
          if (layers != null) {
            throw const PsFormatException(message: 'Multiple Photoshop TIFF layer-info blocks');
          }
          sampleDepth = switch (header.key) {
            'Lr16' => 16,
            'Lr32' => 32,
            _ => depth,
          };
          layers = _readLayerInfo(
            PsBinaryReader(bytes: payload),
            version: version,
            depth: sampleDepth,
            options: options,
            budget: budget,
          );
        case 'LMsk':
          mask = payload;
        default:
          global.add(PsdTaggedBlock(key: header.key, signature: header.signature, data: payload));
      }
      final int padding = (4 - header.declaredLength % 4) % 4;
      if (padding <= blocks.remaining && !PsTaggedBlockCodec.hasSignature(blocks, signatures: _tiffSignatures)) {
        blocks.skip(padding);
      }
    }
    if (![1, 8, 16, 32].contains(sampleDepth)) {
      throw const PsFormatException(message: 'Unsupported Photoshop TIFF depth');
    }
    return PsdTiffData(
      version: version,
      byteOrder: order,
      depth: sampleDepth,
      layers: layers?.layers ?? const [],
      mergedTransparency: layers?.mergedTransparency ?? false,
      globalLayerMaskData: mask,
      additionalLayerInfo: global,
      trailingData: blocks.readBytes(blocks.remaining),
    );
  }

  /// Encodes ImageSourceData; unconvertible opaque blocks cause an explicit error.
  ///
  /// Keep the decoded [PsdTiffData.byteOrder] to retain unknown Intel-order data.
  /// Big-endian output accepts ordinary opaque PSD blocks without conversion.
  static Uint8List encode(PsdTiffData data, {Endian? byteOrder, PsdWriteOptions options = const PsdWriteOptions()}) {
    final Endian order = byteOrder ?? data.byteOrder;
    final PsdVersion version = options.version ?? data.version;
    if (![1, 8, 16, 32].contains(data.depth)) {
      throw const PsWriteException(message: 'Unsupported Photoshop TIFF depth');
    }
    final PsdDocument document = data.toDocument(width: 1, height: 1, channels: 1, colorMode: PsdColorMode.grayscale, mergedImage: const []);
    final PsBinaryWriter writer = PsBinaryWriter();
    final List<PsdTaggedBlock> blocks = [
      if (data.layers.isNotEmpty)
        PsdTaggedBlock(
          key: switch (data.depth) {
            16 => 'Lr16',
            32 => 'Lr32',
            _ => 'Layr',
          },
          data: _writeLayerInfo(document, version: version, options: options),
        ),
      if (data.globalLayerMaskData.isNotEmpty) PsdTaggedBlock(key: 'LMsk', data: data.globalLayerMaskData),
      ...data.additionalLayerInfo,
    ];
    for (final PsdTaggedBlock block in blocks) {
      if (const {'Layr', 'Lr16', 'Lr32'}.contains(block.key) && block != blocks.first) {
        throw const PsWriteException(message: 'Additional blocks contain duplicate layer data');
      }
      PsTaggedBlockCodec.write(
        writer,
        PsTaggedBlock(signature: block.signature, key: block.key, data: block.data),
        alignment: 4,
        wideLengthResolver: (signature, key) => version == PsdVersion.psb && _widePsbTaggedBlocks.contains(key),
      );
    }
    writer.writeBytes(data.trailingData);
    final Uint8List body = writer.takeBytes();
    if (order == Endian.big) {
      _rejectForeignTiffBlocks(document);
    }
    final _PsdTiffTranscoder converter = _PsdTiffTranscoder(source: body, from: Endian.big, to: order, version: version);
    if (order != Endian.big) {
      converter.blocks();
    }
    return (PsBinaryWriter()
          ..writeString(version == PsdVersion.psb ? _wideSignature : _signature)
          ..writeBytes(order == Endian.big ? body : converter.output))
        .takeBytes();
  }

  /// Decodes Photoshop image resources from tag 34377, including Intel envelopes.
  static List<PsdImageResource> decodeResources(Uint8List bytes) {
    final Endian order = _order(bytes);
    final _PsdTiffTranscoder converter = _PsdTiffTranscoder(source: bytes, from: order, to: Endian.big, version: PsdVersion.psd);
    if (order != Endian.big) {
      converter.resources();
    }
    return _readImageResources(PsBinaryReader(bytes: order == Endian.big ? bytes : converter.output));
  }

  /// Writes standard big-endian resource data, independent of TIFF byte order.
  static Uint8List encodeResources(List<PsdImageResource> resources) => _writeImageResources(resources);

  /// Detects the Photoshop structure order rather than assuming the TIFF's order.
  static Endian _order(Uint8List body) {
    if (body.isEmpty) {
      return Endian.big;
    }
    if (body.length < 4) {
      throw const PsFormatException(message: 'Truncated Photoshop TIFF block signature');
    }
    return switch (String.fromCharCodes(body.sublist(0, 4))) {
      '8BIM' || '8B64' => Endian.big,
      'MIB8' || '46B8' => Endian.little,
      _ => throw const PsFormatException(message: 'Invalid Photoshop TIFF block signature'),
    };
  }
}

/// Normal block signatures and internal markers for opaque Intel-order payloads.
const Set<String> _tiffSignatures = {'8BIM', '8B64', 'MIB8', '46B8'};

/// Prevents foreign-order bytes from being written into a standard PSD document.
void _rejectForeignTiffBlocks(PsdDocument document, {Iterable<PsdLayer>? layers}) {
  for (final PsdTaggedBlock block in [...document.additionalLayerInfo, for (final PsdLayer layer in layers ?? document.layers) ...layer.additionalInfo]) {
    if (block.isForeignByteOrder) {
      throw PsWriteException(message: 'Opaque Intel-order ${block.key} data requires TIFF output in its original byte order');
    }
  }
}
