import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:psdkit/src/adjustments.dart';
import 'package:psdkit/src/effects.dart';
import 'package:psdkit/src/fill_content.dart';
import 'package:psdkit/src/filter_effects.dart';
import 'package:psdkit/src/layer_options.dart';
import 'package:psdkit/src/model/copy.dart';
import 'package:psdkit/src/paths.dart';
import 'package:psdkit/src/smart_objects.dart';
import 'package:psdkit/src/text.dart';

part 'model/document.dart';
part 'model/layer.dart';
part 'model/records.dart';

/// Selects the classic PSD or large-document PSB container.
enum PsdVersion {
  /// Photoshop document, with 32-bit section lengths.
  psd(code: 1),

  /// Photoshop large document, with selected 64-bit section lengths.
  psb(code: 2);

  /// Value stored in the file header.
  final int code;

  /// Creates a version from its stored header [code].
  const PsdVersion({required this.code});
}

/// Identifies the document colour model.
enum PsdColorMode {
  /// One bit per pixel.
  bitmap(code: 0),

  /// One grayscale component.
  grayscale(code: 1),

  /// Indexed colour using the color-mode palette.
  indexed(code: 2),

  /// Red, green, and blue components.
  rgb(code: 3),

  /// Cyan, magenta, yellow, and black components.
  cmyk(code: 4),

  /// An arbitrary collection of channels.
  multichannel(code: 7),

  /// Grayscale interpreted through duotone settings.
  duotone(code: 8),

  /// CIE L*a*b* components.
  lab(code: 9);

  /// Value stored in the file header.
  final int code;

  /// Creates a colour mode from its stored header [code].
  const PsdColorMode({required this.code});
}

/// Selects the compression used for a channel or merged image.
enum PsdCompression {
  /// Uncompressed planar samples.
  raw(code: 0),

  /// PackBits compression applied independently to every row.
  rle(code: 1),

  /// A zlib stream without prediction.
  zip(code: 2),

  /// A zlib stream after horizontal prediction.
  zipPrediction(code: 3);

  /// Value stored before the compressed bytes.
  final int code;

  /// Creates a compression mode from its stored [code].
  const PsdCompression({required this.code});
}

/// Describes the semantic role of a layer record in a group hierarchy.
enum PsdSectionType {
  /// A regular layer.
  other(code: 0),

  /// The visible start of an expanded group.
  openFolder(code: 1),

  /// The visible start of a collapsed group.
  closedFolder(code: 2),

  /// The hidden record ending a group.
  boundingDivider(code: 3);

  /// Value stored in an `lsct` tagged block.
  final int code;

  /// Creates a section type from its stored [code].
  const PsdSectionType({required this.code});
}

/// Limits untrusted input before allocating decoded image buffers.
final class PsdReadOptions {
  /// Maximum canvas area.
  final int maxPixels;

  /// Maximum number of layer records.
  final int maxLayers;

  /// Maximum size of any single decoded channel or merged image.
  final int maxDecodedBytes;

  /// Retains compressed payloads for byte-preserving writes of unchanged pixels.
  ///
  /// This copies compressed data and hashes decoded samples. Editors that build
  /// their own document model should leave it disabled.
  final bool preserveSourceEncoding;

  /// Creates defensive parser limits.
  const PsdReadOptions({
    this.preserveSourceEncoding = false,
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
