part of '../image_resources.dart';

/// Photoshop fixed-point document resolution and units.
final class PsdResolutionInfo extends PsdImageResourceData {
  /// Horizontal 16.16 fixed-point resolution.
  final int horizontalFixed;

  /// Horizontal-resolution unit code.
  final int horizontalResolutionUnit;

  /// Width display-unit code.
  final int widthUnit;

  /// Vertical 16.16 fixed-point resolution.
  final int verticalFixed;

  /// Vertical-resolution unit code.
  final int verticalResolutionUnit;

  /// Height display-unit code.
  final int heightUnit;

  /// Creates resolution information from exact fixed-point values.
  const PsdResolutionInfo({
    required this.horizontalFixed,
    required this.horizontalResolutionUnit,
    required this.widthUnit,
    required this.verticalFixed,
    required this.verticalResolutionUnit,
    required this.heightUnit,
  });

  /// Creates resolution information from floating-point values.
  factory PsdResolutionInfo.fromValues({required double horizontal, required double vertical, int resolutionUnit = 1, int displayUnit = 1}) => PsdResolutionInfo(
    horizontalFixed: (horizontal * 65536).round(),
    horizontalResolutionUnit: resolutionUnit,
    widthUnit: displayUnit,
    verticalFixed: (vertical * 65536).round(),
    verticalResolutionUnit: resolutionUnit,
    heightUnit: displayUnit,
  );

  @override
  int get resourceId => PsdImageResourceIds.resolutionInfo;

  /// Horizontal resolution as a floating-point value.
  double get horizontal => horizontalFixed / 65536;

  /// Vertical resolution as a floating-point value.
  double get vertical => verticalFixed / 65536;
}

/// One horizontal or vertical document guide.
final class PsdGuide {
  /// Guide location in Photoshop's 1/32-pixel coordinate units.
  final int location;

  /// Raw direction code.
  final int direction;

  /// Creates a document guide.
  const PsdGuide({required this.location, required this.direction});

  /// Recognized guide direction, or `null` for an unknown code.
  PsdGuideDirection? get directionType {
    for (final PsdGuideDirection value in PsdGuideDirection.values) {
      if (value.code == direction) {
        return value;
      }
    }
    return null;
  }

  /// Guide location in pixels.
  double get pixels => location / 32;
}

/// Grid spacing and document guides.
final class PsdGridAndGuides extends PsdImageResourceData {
  /// Resource format version.
  final int version;

  /// Horizontal grid cycle.
  final int horizontalCycle;

  /// Vertical grid cycle.
  final int verticalCycle;

  /// Ordered document guides.
  final List<PsdGuide> guides;

  /// Creates grid and guide settings.
  const PsdGridAndGuides({this.version = 1, this.horizontalCycle = 576, this.verticalCycle = 576, this.guides = const <PsdGuide>[]});

  @override
  int get resourceId => PsdImageResourceIds.gridAndGuides;
}

/// Photoshop thumbnail header and encoded or raw pixel data.
final class PsdThumbnailResource extends PsdImageResourceData {
  /// Resource identifier distinguishing RGB and historical BGR raw data.
  @override
  final int resourceId;

  /// Zero for raw RGB/BGR or one for JPEG.
  final int format;

  /// Thumbnail width in pixels.
  final int width;

  /// Thumbnail height in pixels.
  final int height;

  /// Padded bytes per raw row.
  final int rowBytes;

  /// Uncompressed payload size recorded by Photoshop.
  final int totalSize;

  /// Bits per pixel, normally 24.
  final int bitsPerPixel;

  /// Number of planes, normally one.
  final int planes;

  /// JPEG stream or raw RGB/BGR pixels.
  final Uint8List data;

  /// Creates thumbnail resource data.
  const PsdThumbnailResource({
    this.resourceId = PsdImageResourceIds.thumbnail,
    required this.format,
    required this.width,
    required this.height,
    required this.rowBytes,
    required this.totalSize,
    required this.bitsPerPixel,
    required this.planes,
    required this.data,
  });

  /// Whether raw pixels use the Photoshop 4 BGR ordering.
  bool get bgr => resourceId == PsdImageResourceIds.thumbnailPhotoshop4;

  /// Whether [data] contains a JPEG stream.
  bool get jpeg => format == 1;
}

/// Header information and complete bytes of an ICC profile.
final class PsdIccProfileResource extends PsdImageResourceData {
  /// Complete ICC profile bytes.
  final Uint8List data;

  /// Creates an ICC-profile resource.
  const PsdIccProfileResource({required this.data});

  @override
  int get resourceId => PsdImageResourceIds.iccProfile;

  /// Profile size declared by the ICC header, when present.
  int? get declaredSize => data.length < 4 ? null : ByteData.sublistView(data).getUint32(0);

  /// Preferred color-management module signature, when present.
  String? get preferredCmm => _asciiAt(data, 4);

  /// Encoded ICC version, when present.
  int? get version => data.length < 12 ? null : ByteData.sublistView(data).getUint32(8);

  /// Profile device-class signature, when present.
  String? get deviceClass => _asciiAt(data, 12);

  /// Input color-space signature, when present.
  String? get colorSpace => _asciiAt(data, 16);

  /// Profile connection-space signature, when present.
  String? get connectionSpace => _asciiAt(data, 20);

  /// Whether the required ICC `acsp` signature is present.
  bool get hasValidSignature => _asciiAt(data, 36) == 'acsp';
}

/// Pixel aspect ratio with its Photoshop resource version.
final class PsdPixelAspectRatio extends PsdImageResourceData {
  /// Resource format version.
  final int version;

  /// Horizontal-to-vertical pixel ratio.
  final double ratio;

  /// Creates pixel-aspect-ratio data.
  const PsdPixelAspectRatio({required this.version, required this.ratio});

  @override
  int get resourceId => PsdImageResourceIds.pixelAspectRatio;
}

/// Photoshop application version information.
final class PsdVersionInfo extends PsdImageResourceData {
  /// Resource format version.
  final int version;

  /// Whether a real merged composite is present.
  final bool hasRealMergedData;

  /// Application that last wrote the file.
  final String writerName;

  /// Intended reader application.
  final String readerName;

  /// Photoshop file-format version recorded by the writer.
  final int fileVersion;

  /// Creates application version information.
  const PsdVersionInfo({required this.version, required this.hasRealMergedData, required this.writerName, required this.readerName, required this.fileVersion});

  @override
  int get resourceId => PsdImageResourceIds.versionInfo;
}

/// One entry in Photoshop's URL list.
final class PsdUrlItem {
  /// Entry sequence number.
  final int number;

  /// Entry identifier.
  final int id;

  /// Unicode URL or associated name.
  final String name;

  /// Creates a URL-list entry.
  const PsdUrlItem({required this.number, required this.id, required this.name});
}

/// Ordered Photoshop URL-list entries.
final class PsdUrlList extends PsdImageResourceData {
  /// URL-list entries.
  final List<PsdUrlItem> items;

  /// Creates URL-list resource data.
  const PsdUrlList({required this.items});

  @override
  int get resourceId => PsdImageResourceIds.urlList;
}

/// A versioned Photoshop action descriptor stored as an image resource.
final class PsdDescriptorImageResource extends PsdImageResourceData {
  /// Resource identifier.
  @override
  final int resourceId;

  /// Descriptor format version, normally 16.
  final int descriptorVersion;

  /// Editable action descriptor.
  final PsDescriptor descriptor;

  /// Bytes following the descriptor.
  final Uint8List trailingData;

  /// Creates descriptor-backed image-resource data.
  const PsdDescriptorImageResource({required this.resourceId, required this.descriptorVersion, required this.descriptor, required this.trailingData});
}

/// Display color and opacity for one alpha channel.
final class PsdAlphaChannelDisplay {
  /// Photoshop color-space code.
  final int colorSpace;

  /// Four raw 16-bit color components.
  final List<int> components;

  /// Opacity from zero through 100.
  final int opacity;

  /// Alpha-channel mode code.
  final int mode;

  /// Creates alpha-channel display information.
  const PsdAlphaChannelDisplay({required this.colorSpace, required this.components, required this.opacity, required this.mode});
}

/// Versioned display settings for alpha channels.
final class PsdDisplayInfo extends PsdImageResourceData {
  /// Resource format version.
  final int version;

  /// Ordered alpha-channel display records.
  final List<PsdAlphaChannelDisplay> channels;

  /// Creates display information.
  const PsdDisplayInfo({required this.version, required this.channels});

  @override
  int get resourceId => PsdImageResourceIds.displayInfo;
}

/// Working or saved vector path stored in image resources.
final class PsdPathImageResource extends PsdImageResourceData {
  /// Working-path or saved-path resource identifier.
  @override
  final int resourceId;

  /// Editable vector path.
  final PsdVectorPath path;

  /// Creates path resource data.
  const PsdPathImageResource({required this.resourceId, required this.path});
}

/// Modern Photoshop slice data stored as a descriptor.
final class PsdSlicesResource extends PsdImageResourceData {
  /// Slice resource version, normally 7 or 8.
  final int version;

  /// Descriptor format version.
  final int descriptorVersion;

  /// Slice descriptor.
  final PsDescriptor descriptor;

  /// Bytes following the descriptor.
  final Uint8List trailingData;

  /// Creates modern slice data.
  const PsdSlicesResource({required this.version, required this.descriptorVersion, required this.descriptor, required this.trailingData});

  @override
  int get resourceId => PsdImageResourceIds.slices;
}
