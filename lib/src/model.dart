import 'dart:typed_data';

import 'package:psdkit/src/effects.dart';
import 'package:psdkit/src/text.dart';

/// Selects the classic PSD or large-document PSB container.
enum PsdVersion {
  /// Photoshop document, with 32-bit section lengths.
  psd(1),

  /// Photoshop large document, with selected 64-bit section lengths.
  psb(2);

  /// Value stored in the file header.
  final int code;

  /// Creates a version from its stored header [code].
  const PsdVersion(this.code);
}

/// Identifies the document colour model.
enum PsdColorMode {
  /// One bit per pixel.
  bitmap(0),

  /// One grayscale component.
  grayscale(1),

  /// Indexed colour using the color-mode palette.
  indexed(2),

  /// Red, green, and blue components.
  rgb(3),

  /// Cyan, magenta, yellow, and black components.
  cmyk(4),

  /// An arbitrary collection of channels.
  multichannel(7),

  /// Grayscale interpreted through duotone settings.
  duotone(8),

  /// CIE L*a*b* components.
  lab(9);

  /// Value stored in the file header.
  final int code;

  /// Creates a colour mode from its stored header [code].
  const PsdColorMode(this.code);
}

/// Selects the compression used for a channel or merged image.
enum PsdCompression {
  /// Uncompressed planar samples.
  raw(0),

  /// PackBits compression applied independently to every row.
  rle(1),

  /// A zlib stream without prediction.
  zip(2),

  /// A zlib stream after horizontal prediction.
  zipPrediction(3);

  /// Value stored before the compressed bytes.
  final int code;

  /// Creates a compression mode from its stored [code].
  const PsdCompression(this.code);
}

/// Describes the semantic role of a layer record in a group hierarchy.
enum PsdSectionType {
  /// A regular layer.
  other(0),

  /// The visible start of an expanded group.
  openFolder(1),

  /// The visible start of a collapsed group.
  closedFolder(2),

  /// The hidden record ending a group.
  boundingDivider(3);

  /// Value stored in an `lsct` tagged block.
  final int code;

  /// Creates a section type from its stored [code].
  const PsdSectionType(this.code);
}

/// A rectangle in document pixel coordinates.
final class PsdRectangle {
  /// Top edge.
  final int top;

  /// Left edge.
  final int left;

  /// Bottom edge.
  final int bottom;

  /// Right edge.
  final int right;

  /// Creates a rectangle from its four PSD edges.
  const PsdRectangle({
    required this.top,
    required this.left,
    required this.bottom,
    required this.right,
  });

  /// Creates a rectangle whose origin is zero.
  const PsdRectangle.fromSize({required int width, required int height}) : this(top: 0, left: 0, bottom: height, right: width);

  /// Non-negative pixel width.
  int get width => (right - left).clamp(0, 0x7fffffff);

  /// Non-negative pixel height.
  int get height => (bottom - top).clamp(0, 0x7fffffff);
}

/// An opaque Photoshop image resource block.
final class PsdImageResource {
  /// Numeric resource identifier.
  final int id;

  /// Pascal-string resource name.
  final String name;

  /// Four-character block signature.
  final String signature;

  /// Uninterpreted resource payload.
  final Uint8List data;

  /// Creates a resource that can be preserved during a read/write cycle.
  const PsdImageResource({
    required this.id,
    required this.data,
    this.name = '',
    this.signature = '8BIM',
  });
}

/// An opaque additional-layer-information block.
final class PsdTaggedBlock {
  /// Four-character block key.
  final String key;

  /// Four-character block signature.
  final String signature;

  /// Uninterpreted block payload, without alignment padding.
  final Uint8List data;

  /// Creates a block that can be interpreted by clients or preserved verbatim.
  const PsdTaggedBlock({
    required this.key,
    required this.data,
    this.signature = '8BIM',
  });
}

/// Parsed layer-mask metadata.
final class PsdLayerMask {
  /// Bounds of channel `-2`.
  final PsdRectangle rectangle;

  /// Value used outside the mask bounds.
  final int defaultColor;

  /// Primary mask flags.
  final int flags;

  /// Bounds of channel `-3`, when present.
  final PsdRectangle? realRectangle;

  /// Real-mask flags, when present.
  final int? realFlags;

  /// Real-mask default value, when present.
  final int? realDefaultColor;

  /// Original payload for fields not interpreted by PsdKit.
  final Uint8List data;

  /// Creates layer-mask metadata while retaining its complete binary payload.
  const PsdLayerMask({
    required this.rectangle,
    required this.defaultColor,
    required this.flags,
    required this.data,
    this.realRectangle,
    this.realFlags,
    this.realDefaultColor,
  });
}

/// Uncompressed samples for one layer channel.
final class PsdChannel {
  /// Component id, where `-1` is transparency and `-2` is the user mask.
  final int id;

  /// Big-endian sample bytes in row-major order.
  final Uint8List data;

  /// Preferred encoding when the document is written.
  final PsdCompression compression;

  /// Creates channel samples.
  const PsdChannel({
    required this.id,
    required this.data,
    this.compression = PsdCompression.rle,
  });
}

/// A Photoshop layer record and its decoded channels.
final class PsdLayer {
  /// Pixel bounds in document coordinates.
  final PsdRectangle rectangle;

  /// Unicode display name, falling back to the Pascal name on import.
  final String name;

  /// Decoded planar channels.
  final List<PsdChannel> channels;

  /// Four-character Photoshop blend-mode key.
  final String blendMode;

  /// Opacity from 0 through 255.
  final int opacity;

  /// Clipping flag, normally 0 or 1.
  final int clipping;

  /// Raw layer flags. Bit 1 means hidden in PSD files.
  final int flags;

  /// Raster-mask metadata, when present.
  final PsdLayerMask? mask;

  /// Opaque layer blending-ranges payload.
  final Uint8List blendingRanges;

  /// Tagged data such as text, effects, vector paths, and adjustment settings.
  final List<PsdTaggedBlock> additionalInfo;

  /// Creates a layer.
  PsdLayer({
    required this.rectangle,
    required this.name,
    this.channels = const [],
    this.blendMode = 'norm',
    this.opacity = 255,
    this.clipping = 0,
    this.flags = 0,
    this.mask,
    Uint8List? blendingRanges,
    this.additionalInfo = const [],
  }) : blendingRanges = blendingRanges ?? Uint8List(0);

  /// Whether the layer is visible.
  bool get visible => flags & 0x02 == 0;

  /// Decoded Photoshop type-tool data, when this is a supported text layer.
  PsdTypeTool? get typeTool {
    final PsdTaggedBlock? block = taggedBlock('TySh');
    return block == null ? null : PsdTypeToolCodec.tryDecode(block.data);
  }

  /// Decoded Photoshop layer effects, preferring the modern descriptor block.
  PsdLayerEffects? get effects {
    for (final String key in const <String>['lfx2', 'lmfx', 'lrFX']) {
      final PsdTaggedBlock? block = taggedBlock(key);
      if (block != null) {
        final PsdLayerEffects? decoded = PsdLayerEffectsCodec.tryDecode(block.data, key: key);
        if (decoded != null) {
          return decoded;
        }
      }
    }
    return null;
  }

  /// Stable Photoshop layer id, when the `lyid` block is present.
  int? get id {
    final PsdTaggedBlock? block = taggedBlock('lyid');
    if (block == null || block.data.length < 4) {
      return null;
    }
    return ByteData.sublistView(block.data).getUint32(0);
  }

  /// Group marker represented by the `lsct` or `lsdk` block.
  PsdSectionType get sectionType {
    final PsdTaggedBlock? block = taggedBlock('lsct') ?? taggedBlock('lsdk');
    if (block == null || block.data.length < 4) {
      return PsdSectionType.other;
    }
    final int code = ByteData.sublistView(block.data).getUint32(0);
    return PsdSectionType.values.firstWhere(
      (value) => value.code == code,
      orElse: () => PsdSectionType.other,
    );
  }

  /// Returns the last tagged block matching [key].
  PsdTaggedBlock? taggedBlock(String key) {
    for (final PsdTaggedBlock block in additionalInfo.reversed) {
      if (block.key == key) {
        return block;
      }
    }
    return null;
  }

  /// Returns the channel with [id], when present.
  PsdChannel? channel(int id) {
    for (final PsdChannel channel in channels) {
      if (channel.id == id) {
        return channel;
      }
    }
    return null;
  }

  /// Returns a copy whose `TySh` block contains [typeTool].
  PsdLayer withTypeTool(PsdTypeTool typeTool) {
    final List<PsdTaggedBlock> blocks = <PsdTaggedBlock>[];
    bool replaced = false;
    for (final PsdTaggedBlock block in additionalInfo) {
      if (block.key == 'TySh') {
        if (!replaced) {
          blocks.add(PsdTaggedBlock(key: 'TySh', data: PsdTypeToolCodec.encode(typeTool)));
        }
        replaced = true;
      } else {
        blocks.add(block);
      }
    }
    if (!replaced) {
      blocks.add(PsdTaggedBlock(key: 'TySh', data: PsdTypeToolCodec.encode(typeTool)));
    }
    return PsdLayer(
      rectangle: rectangle,
      name: name,
      channels: channels,
      blendMode: blendMode,
      opacity: opacity,
      clipping: clipping,
      flags: flags,
      mask: mask,
      blendingRanges: blendingRanges,
      additionalInfo: blocks,
    );
  }

  /// Returns a copy whose effect blocks contain [effects].
  ///
  /// Replacing effects removes stale modern and legacy effect blocks so that
  /// Photoshop cannot select an older conflicting representation.
  PsdLayer withEffects(PsdLayerEffects effects) {
    final List<PsdTaggedBlock> blocks = <PsdTaggedBlock>[
      for (final PsdTaggedBlock block in additionalInfo)
        if (block.key != 'lfx2' && block.key != 'lmfx' && block.key != 'lrFX') block,
      PsdTaggedBlock(key: effects.blockKey, data: PsdLayerEffectsCodec.encode(effects)),
    ];
    return PsdLayer(
      rectangle: rectangle,
      name: name,
      channels: channels,
      blendMode: blendMode,
      opacity: opacity,
      clipping: clipping,
      flags: flags,
      mask: mask,
      blendingRanges: blendingRanges,
      additionalInfo: blocks,
    );
  }
}

/// An in-memory PSD or PSB document.
final class PsdDocument {
  /// Container version.
  final PsdVersion version;

  /// Canvas width in pixels.
  final int width;

  /// Canvas height in pixels.
  final int height;

  /// Number of channels in the merged image.
  final int channels;

  /// Bits per sample: 1, 8, 16, or 32.
  final int depth;

  /// Document colour model.
  final PsdColorMode colorMode;

  /// Palette, duotone settings, or other mode-specific bytes.
  final Uint8List colorModeData;

  /// Photoshop image resource blocks.
  final List<PsdImageResource> imageResources;

  /// Flat PSD layer-record order, including group divider records.
  final List<PsdLayer> layers;

  /// Merged-image channels in file order.
  final List<Uint8List> mergedImage;

  /// Preferred merged-image encoding.
  final PsdCompression mergedImageCompression;

  /// Whether a negative layer count advertised merged transparency.
  final bool mergedTransparency;

  /// Opaque global layer-mask payload.
  final Uint8List globalLayerMaskData;

  /// Tagged blocks following global layer-mask information.
  final List<PsdTaggedBlock> additionalLayerInfo;

  /// Creates a document from planar, uncompressed channel samples.
  PsdDocument({
    required this.width,
    required this.height,
    required this.channels,
    required this.depth,
    required this.colorMode,
    required this.mergedImage,
    this.version = PsdVersion.psd,
    Uint8List? colorModeData,
    this.imageResources = const [],
    this.layers = const [],
    this.mergedImageCompression = PsdCompression.rle,
    this.mergedTransparency = false,
    Uint8List? globalLayerMaskData,
    this.additionalLayerInfo = const [],
  }) : colorModeData = colorModeData ?? Uint8List(0),
       globalLayerMaskData = globalLayerMaskData ?? Uint8List(0);
}

/// Limits untrusted input before allocating decoded image buffers.
final class PsdReadOptions {
  /// Maximum canvas area.
  final int maxPixels;

  /// Maximum number of layer records.
  final int maxLayers;

  /// Maximum size of any single decoded channel or merged image.
  final int maxDecodedBytes;

  /// Creates defensive parser limits.
  const PsdReadOptions({
    this.maxPixels = 500000000,
    this.maxLayers = 100000,
    this.maxDecodedBytes = 2147483648,
  });
}

/// Controls container version and default compression during encoding.
final class PsdWriteOptions {
  /// Overrides the document container version.
  final PsdVersion? version;

  /// Overrides every channel's preferred compression.
  final PsdCompression? compression;

  /// Creates write options.
  const PsdWriteOptions({this.version, this.compression});
}
