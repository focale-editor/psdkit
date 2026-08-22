import 'dart:convert';
import 'dart:typed_data';

import 'package:psdkit/src/binary.dart';
import 'package:psdkit/src/descriptor.dart';
import 'package:psdkit/src/exceptions.dart';
import 'package:psdkit/src/model.dart';
import 'package:psdkit/src/paths.dart';

/// Standard Photoshop image-resource identifiers.
abstract final class PsdImageResourceIds {
  /// Resolution information.
  static const int resolutionInfo = 1005;

  /// Pascal-string alpha-channel names.
  static const int alphaNamesPascal = 1006;

  /// Document background color.
  static const int backgroundColor = 1010;

  /// Page-setup print flags.
  static const int printFlags = 1011;

  /// Grayscale halftone screens.
  static const int grayscaleHalftoning = 1012;

  /// Color halftone screens.
  static const int colorHalftoning = 1013;

  /// Duotone halftone screens.
  static const int duotoneHalftoning = 1014;

  /// Grayscale transfer functions.
  static const int grayscaleTransferFunctions = 1015;

  /// Color transfer functions.
  static const int colorTransferFunctions = 1016;

  /// Duotone transfer functions.
  static const int duotoneTransferFunctions = 1017;

  /// Selected layer index.
  static const int layerState = 1024;

  /// Unsaved working path.
  static const int workingPath = 1025;

  /// Layer-group identifiers.
  static const int layerGroups = 1026;

  /// IPTC-NAA metadata.
  static const int iptc = 1028;

  /// Grid and guide settings.
  static const int gridAndGuides = 1032;

  /// Photoshop 4 thumbnail.
  static const int thumbnailPhotoshop4 = 1033;

  /// Copyright flag.
  static const int copyrightFlag = 1034;

  /// URL stored as a one-byte string.
  static const int url = 1035;

  /// Photoshop 5 and later thumbnail.
  static const int thumbnail = 1036;

  /// Global lighting angle.
  static const int globalAngle = 1037;

  /// ICC profile bytes.
  static const int iccProfile = 1039;

  /// Watermark flag.
  static const int watermark = 1040;

  /// Intentionally untagged ICC flag.
  static const int iccUntagged = 1041;

  /// Global layer-effects visibility.
  static const int effectsVisible = 1042;

  /// Seed for document-scoped layer identifiers.
  static const int documentIdSeed = 1044;

  /// Unicode alpha-channel names.
  static const int alphaNamesUnicode = 1045;

  /// Number of defined indexed colors.
  static const int indexedColorCount = 1046;

  /// Indexed transparency entry.
  static const int transparencyIndex = 1047;

  /// Global lighting altitude.
  static const int globalAltitude = 1049;

  /// Slice definitions.
  static const int slices = 1050;

  /// Workflow URL stored as Unicode.
  static const int workflowUrl = 1051;

  /// Alpha-channel identifiers.
  static const int alphaIdentifiers = 1053;

  /// URL list.
  static const int urlList = 1054;

  /// Photoshop writer and reader version information.
  static const int versionInfo = 1057;

  /// Primary EXIF block.
  static const int exif1 = 1058;

  /// Secondary EXIF block.
  static const int exif3 = 1059;

  /// UTF-8 XMP packet.
  static const int xmp = 1060;

  /// Sixteen-byte IPTC caption digest.
  static const int captionDigest = 1061;

  /// Print scale and placement.
  static const int printScale = 1062;

  /// Pixel aspect ratio.
  static const int pixelAspectRatio = 1064;

  /// Layer-comps descriptor.
  static const int layerComps = 1065;

  /// Selected layer identifiers.
  static const int layerSelectionIds = 1069;

  /// Per-layer group enabled flags.
  static const int layerGroupEnabled = 1072;

  /// Alpha-channel display information.
  static const int displayInfo = 1077;

  /// Photoshop CS5 print-information descriptor.
  static const int printInfo = 1082;

  /// Photoshop CS5 print-style descriptor.
  static const int printStyle = 1083;

  /// Auto-save path stored as Unicode.
  static const int autoSavePath = 1086;

  /// Auto-save format stored as Unicode.
  static const int autoSaveFormat = 1087;

  /// Current path-selection descriptor.
  static const int pathSelectionState = 1088;

  /// Clipping-path name and options.
  static const int clippingPathName = 2999;

  /// Origin-path descriptor.
  static const int originPathInfo = 3000;

  /// Extended print flags.
  static const int printFlagsInfo = 10000;

  /// Whether [id] contains a saved vector path.
  static bool isPath(int id) => id >= 2000 && id <= 2997;

  /// Whether [id] is reserved for a plug-in-defined resource.
  static bool isPlugin(int id) => id >= 4000 && id <= 4999;
}

/// Controls the count prefix used by an integer-list resource.
enum PsdImageResourceListLayout {
  /// Values fill the complete payload without a count.
  uncounted,

  /// A two-byte count precedes the values.
  uint16Count,

  /// A four-byte count precedes the values.
  uint32Count,
}

/// Describes the placement policy used for printing.
enum PsdPrintScaleStyle {
  /// Centers the image.
  centered(0),

  /// Scales the image to fit the page.
  sizeToFit(1),

  /// Uses explicit position and scale values.
  userDefined(2);

  /// Stored two-byte style code.
  final int code;

  /// Creates a style from its stored [code].
  const PsdPrintScaleStyle(this.code);
}

/// Direction of a Photoshop guide.
enum PsdGuideDirection {
  /// Vertical guide.
  vertical(0),

  /// Horizontal guide.
  horizontal(1);

  /// Stored one-byte direction code.
  final int code;

  /// Creates a guide direction from its [code].
  const PsdGuideDirection(this.code);
}

/// Semantic or explicitly opaque payload of one image-resource block.
sealed class PsdImageResourceData {
  /// Creates an image-resource data value.
  const PsdImageResourceData();

  /// Resource identifier accepted by this value.
  int get resourceId;
}

/// Bytes belonging to an unknown or private resource format.
final class PsdRawImageResource extends PsdImageResourceData {
  /// Resource identifier.
  @override
  final int resourceId;

  /// Uninterpreted resource bytes.
  final Uint8List data;

  /// Creates an opaque image-resource value.
  const PsdRawImageResource({required this.resourceId, required this.data});
}

/// Document metadata whose external binary standard is retained verbatim.
final class PsdBinaryMetadataResource extends PsdImageResourceData {
  /// Resource identifier.
  @override
  final int resourceId;

  /// Complete IPTC, EXIF, digest, or platform payload.
  final Uint8List data;

  /// Creates a binary metadata resource.
  const PsdBinaryMetadataResource({required this.resourceId, required this.data});
}

/// A one-byte image-resource value.
final class PsdByteImageResource extends PsdImageResourceData {
  /// Resource identifier.
  @override
  final int resourceId;

  /// Unsigned stored value.
  final int value;

  /// Creates a byte resource.
  const PsdByteImageResource({required this.resourceId, required this.value});
}

/// A two-byte image-resource value.
final class PsdShortImageResource extends PsdImageResourceData {
  /// Resource identifier.
  @override
  final int resourceId;

  /// Unsigned stored value.
  final int value;

  /// Creates a short-integer resource.
  const PsdShortImageResource({required this.resourceId, required this.value});
}

/// A signed four-byte image-resource value.
final class PsdIntegerImageResource extends PsdImageResourceData {
  /// Resource identifier.
  @override
  final int resourceId;

  /// Signed stored value.
  final int value;

  /// Creates an integer resource.
  const PsdIntegerImageResource({required this.resourceId, required this.value});
}

/// A sequence of one-byte values consuming the complete payload.
final class PsdByteListImageResource extends PsdImageResourceData {
  /// Resource identifier.
  @override
  final int resourceId;

  /// Ordered unsigned byte values.
  final List<int> values;

  /// Creates a byte-list resource.
  const PsdByteListImageResource({required this.resourceId, required this.values});
}

/// A sequence of fixed-width unsigned integers.
final class PsdIntegerListImageResource extends PsdImageResourceData {
  /// Resource identifier.
  @override
  final int resourceId;

  /// Ordered integer values.
  final List<int> values;

  /// Bytes occupied by each value, either two or four.
  final int valueBytes;

  /// Count prefix representation.
  final PsdImageResourceListLayout layout;

  /// Creates an integer-list resource.
  const PsdIntegerListImageResource({required this.resourceId, required this.values, required this.valueBytes, this.layout = PsdImageResourceListLayout.uncounted});
}

/// A list of Pascal or UTF-16 image-resource strings.
final class PsdStringListImageResource extends PsdImageResourceData {
  /// Resource identifier.
  @override
  final int resourceId;

  /// Ordered decoded strings.
  final List<String> values;

  /// Whether strings use Photoshop's UTF-16 representation.
  final bool unicode;

  /// Creates a string-list resource.
  const PsdStringListImageResource({required this.resourceId, required this.values, required this.unicode});
}

/// A single Unicode or UTF-8 image-resource string.
final class PsdTextImageResource extends PsdImageResourceData {
  /// Resource identifier.
  @override
  final int resourceId;

  /// Decoded text.
  final String value;

  /// Whether the stored representation is UTF-8 rather than PSD UTF-16.
  final bool utf8;

  /// Original bytes used to retain an unchanged UTF-8 packet exactly.
  final Uint8List? _sourceData;

  /// Original decoded text corresponding to [_sourceData].
  final String? _sourceValue;

  /// Creates an editable text resource.
  PsdTextImageResource({required this.resourceId, required this.value, required this.utf8}) : _sourceData = null, _sourceValue = null;

  /// Creates decoded text while retaining its exact original byte representation.
  PsdTextImageResource._decoded({required this.resourceId, required this.value, required this.utf8, required this._sourceData}) : _sourceValue = value;
}

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

/// A Photoshop color-space code and four unsigned components.
final class PsdImageResourceColor extends PsdImageResourceData {
  /// Photoshop color-space code.
  final int colorSpace;

  /// Four raw 16-bit color components.
  final List<int> components;

  /// Creates an image-resource color.
  const PsdImageResourceColor({required this.colorSpace, required this.components});

  @override
  int get resourceId => PsdImageResourceIds.backgroundColor;
}

/// Boolean flags from Photoshop's page-setup dialog.
final class PsdPrintFlags extends PsdImageResourceData {
  /// Whether labels are printed.
  final bool labels;

  /// Whether crop marks are printed.
  final bool cropMarks;

  /// Whether color bars are printed.
  final bool colorBars;

  /// Whether registration marks are printed.
  final bool registrationMarks;

  /// Whether the image is printed as a negative.
  final bool negative;

  /// Whether the image is flipped.
  final bool flip;

  /// Whether interpolation is enabled.
  final bool interpolate;

  /// Whether a caption is printed.
  final bool caption;

  /// Optional ninth flag used by newer Photoshop versions.
  final bool? printFlags;

  /// Creates page-setup print flags.
  const PsdPrintFlags({
    this.labels = false,
    this.cropMarks = false,
    this.colorBars = false,
    this.registrationMarks = false,
    this.negative = false,
    this.flip = false,
    this.interpolate = false,
    this.caption = false,
    this.printFlags,
  });

  @override
  int get resourceId => PsdImageResourceIds.printFlags;
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

/// One plate's halftone-screen settings.
final class PsdHalftoneScreen {
  /// Screen frequency.
  final double frequency;

  /// Frequency-unit code.
  final int unit;

  /// Screen angle.
  final double angle;

  /// Dot-shape code.
  final int shape;

  /// Whether accurate screens are requested.
  final bool useAccurate;

  /// Whether printer defaults are requested.
  final bool usePrinter;

  /// Creates halftone-screen settings.
  const PsdHalftoneScreen({required this.frequency, required this.unit, required this.angle, required this.shape, this.useAccurate = false, this.usePrinter = false});
}

/// Halftone screens stored for one or more color plates.
final class PsdHalftoneScreens extends PsdImageResourceData {
  /// Resource identifier selecting grayscale, color, or duotone screens.
  @override
  final int resourceId;

  /// Ordered plate settings.
  final List<PsdHalftoneScreen> screens;

  /// Creates halftone-screen resource data.
  const PsdHalftoneScreens({required this.resourceId, required this.screens});
}

/// One plate's transfer curve.
final class PsdTransferFunction {
  /// Thirteen signed curve control points.
  final List<int> curve;

  /// Nonzero when this curve overrides the default.
  final int override;

  /// Creates a transfer function.
  const PsdTransferFunction({required this.curve, this.override = 0});
}

/// Transfer functions stored for one or more color plates.
final class PsdTransferFunctions extends PsdImageResourceData {
  /// Resource identifier selecting grayscale, color, or duotone curves.
  @override
  final int resourceId;

  /// Ordered transfer functions.
  final List<PsdTransferFunction> functions;

  /// Creates transfer-function resource data.
  const PsdTransferFunctions({required this.resourceId, required this.functions});
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
  const PsdIccProfileResource(this.data);

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

/// Page position and scale used when printing.
final class PsdPrintScale extends PsdImageResourceData {
  /// Raw print-style code.
  final int style;

  /// Horizontal page location.
  final double x;

  /// Vertical page location.
  final double y;

  /// Print scale.
  final double scale;

  /// Creates print-scale data.
  const PsdPrintScale({required this.style, required this.x, required this.y, required this.scale});

  @override
  int get resourceId => PsdImageResourceIds.printScale;

  /// Recognized print style, or `null` for an unknown code.
  PsdPrintScaleStyle? get styleType {
    for (final PsdPrintScaleStyle value in PsdPrintScaleStyle.values) {
      if (value.code == style) {
        return value;
      }
    }
    return null;
  }
}

/// Extended crop-mark and bleed print settings.
final class PsdPrintFlagsInfo extends PsdImageResourceData {
  /// Resource format version.
  final int version;

  /// Whether crop marks are centered.
  final bool centerCropMarks;

  /// Reserved byte retained for exact round-trips.
  final int reserved;

  /// Bleed-width fixed value.
  final int bleedWidth;

  /// Bleed-width unit or scale code.
  final int bleedScale;

  /// Creates extended print flags.
  const PsdPrintFlagsInfo({required this.version, required this.centerCropMarks, this.reserved = 0, required this.bleedWidth, required this.bleedScale});

  @override
  int get resourceId => PsdImageResourceIds.printFlagsInfo;
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
  const PsdUrlList(this.items);

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
  final PsdDescriptor descriptor;

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
  final PsdDescriptor descriptor;

  /// Bytes following the descriptor.
  final Uint8List trailingData;

  /// Creates modern slice data.
  const PsdSlicesResource({required this.version, required this.descriptorVersion, required this.descriptor, required this.trailingData});

  @override
  int get resourceId => PsdImageResourceIds.slices;
}

/// Encodes and decodes semantic Photoshop image-resource payloads.
abstract final class PsdImageResourceCodec {
  /// Decodes [data] according to [resourceId].
  static PsdImageResourceData decode(Uint8List data, {required int resourceId}) {
    final PsdBinaryReader reader = PsdBinaryReader(data);
    final PsdImageResourceData decoded = _readImageResource(reader, resourceId);
    if (!reader.isAtEnd) {
      throw PsdFormatException('Unexpected bytes after image resource $resourceId', data, reader.offset);
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
    final PsdBinaryWriter writer = PsdBinaryWriter();
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
      throw PsdWriteException('Resource value ${value.resourceId} cannot replace block $id');
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

/// Resource ids whose public format is an external or intentionally opaque byte stream.
const Set<int> _binaryResourceIds = <int>{
  1000,
  1001,
  1002,
  1003,
  1007,
  1008,
  1009,
  1018,
  1019,
  1020,
  1021,
  1022,
  1023,
  PsdImageResourceIds.iptc,
  1029,
  1030,
  PsdImageResourceIds.url,
  1038,
  1043,
  1052,
  PsdImageResourceIds.exif1,
  PsdImageResourceIds.exif3,
  PsdImageResourceIds.captionDigest,
  1066,
  1067,
  1070,
  1071,
  1073,
  1084,
  1085,
  7000,
  7001,
  7002,
  7003,
  7004,
  7005,
  7006,
  8000,
};

/// Descriptor-backed image-resource ids.
const Set<int> _descriptorResourceIds = <int>{1065, 1074, 1075, 1076, 1078, 1080, 1082, 1083, 1088, 3000};

/// Reads one resource model while consuming [reader] completely.
PsdImageResourceData _readImageResource(PsdBinaryReader reader, int resourceId) {
  if (PsdImageResourceIds.isPath(resourceId) || resourceId == PsdImageResourceIds.workingPath) {
    final Uint8List bytes = reader.readBytes(reader.remaining);
    return PsdPathImageResource(resourceId: resourceId, path: PsdVectorPathCodec.decode(bytes));
  }
  if (resourceId == PsdImageResourceIds.iccProfile) {
    return PsdIccProfileResource(reader.readBytes(reader.remaining));
  }
  if (resourceId == PsdImageResourceIds.xmp) {
    final Uint8List bytes = reader.readBytes(reader.remaining);
    return PsdTextImageResource._decoded(resourceId: resourceId, value: utf8.decode(bytes, allowMalformed: true), utf8: true, sourceData: bytes);
  }
  if (_binaryResourceIds.contains(resourceId)) {
    return PsdBinaryMetadataResource(resourceId: resourceId, data: reader.readBytes(reader.remaining));
  }
  if (_descriptorResourceIds.contains(resourceId)) {
    return _readDescriptorResource(reader, resourceId);
  }
  return switch (resourceId) {
    PsdImageResourceIds.resolutionInfo => PsdResolutionInfo(
      horizontalFixed: reader.readUint32(),
      horizontalResolutionUnit: reader.readUint16(),
      widthUnit: reader.readUint16(),
      verticalFixed: reader.readUint32(),
      verticalResolutionUnit: reader.readUint16(),
      heightUnit: reader.readUint16(),
    ),
    PsdImageResourceIds.alphaNamesPascal => PsdStringListImageResource(resourceId: resourceId, values: _readPascalStrings(reader), unicode: false),
    PsdImageResourceIds.backgroundColor => PsdImageResourceColor(
      colorSpace: reader.readUint16(),
      components: <int>[for (int index = 0; index < 4; index++) reader.readUint16()],
    ),
    PsdImageResourceIds.printFlags => _readPrintFlags(reader),
    PsdImageResourceIds.grayscaleHalftoning || PsdImageResourceIds.colorHalftoning || PsdImageResourceIds.duotoneHalftoning => _readHalftoneScreens(reader, resourceId),
    PsdImageResourceIds.grayscaleTransferFunctions || PsdImageResourceIds.colorTransferFunctions || PsdImageResourceIds.duotoneTransferFunctions => _readTransferFunctions(
      reader,
      resourceId,
    ),
    PsdImageResourceIds.layerState || PsdImageResourceIds.indexedColorCount || PsdImageResourceIds.transparencyIndex => PsdShortImageResource(
      resourceId: resourceId,
      value: reader.readUint16(),
    ),
    PsdImageResourceIds.layerGroups => PsdIntegerListImageResource(
      resourceId: resourceId,
      values: _readUnsignedIntegers(reader, 2),
      valueBytes: 2,
    ),
    PsdImageResourceIds.gridAndGuides => _readGridAndGuides(reader),
    PsdImageResourceIds.thumbnailPhotoshop4 || PsdImageResourceIds.thumbnail => _readThumbnail(reader, resourceId),
    PsdImageResourceIds.copyrightFlag ||
    PsdImageResourceIds.watermark ||
    PsdImageResourceIds.iccUntagged ||
    PsdImageResourceIds.effectsVisible => PsdByteImageResource(resourceId: resourceId, value: reader.readUint8()),
    PsdImageResourceIds.globalAngle || PsdImageResourceIds.documentIdSeed || PsdImageResourceIds.globalAltitude => PsdIntegerImageResource(
      resourceId: resourceId,
      value: reader.readInt32(),
    ),
    PsdImageResourceIds.alphaNamesUnicode => PsdStringListImageResource(resourceId: resourceId, values: _readUnicodeStrings(reader), unicode: true),
    PsdImageResourceIds.slices => _readSlices(reader),
    PsdImageResourceIds.workflowUrl || PsdImageResourceIds.autoSavePath || PsdImageResourceIds.autoSaveFormat => PsdTextImageResource._decoded(
      resourceId: resourceId,
      value: _readUnicodeString(reader),
      utf8: false,
      sourceData: Uint8List(0),
    ),
    PsdImageResourceIds.alphaIdentifiers => PsdIntegerListImageResource(
      resourceId: resourceId,
      values: _readUnsignedIntegers(reader, 4),
      valueBytes: 4,
    ),
    PsdImageResourceIds.urlList => _readUrlList(reader),
    PsdImageResourceIds.versionInfo => _readVersionInfo(reader),
    PsdImageResourceIds.printScale => PsdPrintScale(style: reader.readUint16(), x: reader.readFloat32(), y: reader.readFloat32(), scale: reader.readFloat32()),
    PsdImageResourceIds.pixelAspectRatio => PsdPixelAspectRatio(version: reader.readUint32(), ratio: reader.readFloat64()),
    PsdImageResourceIds.layerSelectionIds => _readLayerSelectionIds(reader),
    PsdImageResourceIds.layerGroupEnabled => PsdByteListImageResource(resourceId: resourceId, values: reader.readBytes(reader.remaining)),
    PsdImageResourceIds.displayInfo => _readDisplayInfo(reader),
    PsdImageResourceIds.printFlagsInfo => PsdPrintFlagsInfo(
      version: reader.readUint16(),
      centerCropMarks: reader.readUint8() != 0,
      reserved: reader.readUint8(),
      bleedWidth: reader.readUint32(),
      bleedScale: reader.readUint16(),
    ),
    _ => PsdRawImageResource(resourceId: resourceId, data: reader.readBytes(reader.remaining)),
  };
}

/// Writes one semantic resource model.
void _writeImageResource(PsdBinaryWriter writer, PsdImageResourceData value) {
  switch (value) {
    case PsdRawImageResource():
      writer.writeBytes(value.data);
    case PsdBinaryMetadataResource():
      writer.writeBytes(value.data);
    case PsdByteImageResource():
      _requireUnsigned(value.value, 8, 'image-resource byte');
      writer.writeUint8(value.value);
    case PsdShortImageResource():
      _requireUnsigned(value.value, 16, 'image-resource short');
      writer.writeUint16(value.value);
    case PsdIntegerImageResource():
      writer.writeInt32(value.value);
    case PsdByteListImageResource():
      for (final int item in value.values) {
        _requireUnsigned(item, 8, 'image-resource byte-list item');
        writer.writeUint8(item);
      }
    case PsdIntegerListImageResource():
      _writeIntegerList(writer, value);
    case PsdStringListImageResource():
      for (final String item in value.values) {
        if (value.unicode) {
          _writeUnicodeString(writer, item);
        } else {
          _writePascalString(writer, item);
        }
      }
    case PsdTextImageResource():
      if (value.utf8) {
        final Uint8List? sourceData = value._sourceData;
        if (sourceData != null && value.value == value._sourceValue) {
          writer.writeBytes(sourceData);
        } else {
          writer.writeBytes(utf8.encode(value.value));
        }
      } else {
        _writeUnicodeString(writer, value.value);
      }
    case PsdResolutionInfo():
      writer
        ..writeUint32(value.horizontalFixed)
        ..writeUint16(value.horizontalResolutionUnit)
        ..writeUint16(value.widthUnit)
        ..writeUint32(value.verticalFixed)
        ..writeUint16(value.verticalResolutionUnit)
        ..writeUint16(value.heightUnit);
    case PsdImageResourceColor():
      if (value.components.length != 4) {
        throw const PsdWriteException('Image-resource colors require four components');
      }
      writer.writeUint16(value.colorSpace);
      value.components.forEach(writer.writeUint16);
    case PsdPrintFlags():
      final List<bool> flags = <bool>[value.labels, value.cropMarks, value.colorBars, value.registrationMarks, value.negative, value.flip, value.interpolate, value.caption];
      if (value.printFlags case final bool flag) {
        flags.add(flag);
      }
      for (final bool flag in flags) {
        writer.writeUint8(flag ? 1 : 0);
      }
    case PsdGridAndGuides():
      writer
        ..writeUint32(value.version)
        ..writeUint32(value.horizontalCycle)
        ..writeUint32(value.verticalCycle)
        ..writeUint32(value.guides.length);
      for (final PsdGuide guide in value.guides) {
        writer
          ..writeUint32(guide.location)
          ..writeUint8(guide.direction);
      }
    case PsdHalftoneScreens():
      for (final PsdHalftoneScreen screen in value.screens) {
        writer
          ..writeUint32((screen.frequency * 65536).round())
          ..writeUint16(screen.unit)
          ..writeInt32((screen.angle * 65536).round())
          ..writeUint16(screen.shape)
          ..writeZeros(4)
          ..writeUint8(screen.useAccurate ? 1 : 0)
          ..writeUint8(screen.usePrinter ? 1 : 0);
      }
    case PsdTransferFunctions():
      for (final PsdTransferFunction function in value.functions) {
        if (function.curve.length != 13) {
          throw const PsdWriteException('Transfer functions require thirteen curve values');
        }
        function.curve.forEach(writer.writeInt16);
        writer.writeUint16(function.override);
      }
    case PsdThumbnailResource():
      writer
        ..writeUint32(value.format)
        ..writeUint32(value.width)
        ..writeUint32(value.height)
        ..writeUint32(value.rowBytes)
        ..writeUint32(value.totalSize)
        ..writeUint32(value.data.length)
        ..writeUint16(value.bitsPerPixel)
        ..writeUint16(value.planes)
        ..writeBytes(value.data);
    case PsdIccProfileResource():
      writer.writeBytes(value.data);
    case PsdPixelAspectRatio():
      writer
        ..writeUint32(value.version)
        ..writeFloat64(value.ratio);
    case PsdPrintScale():
      writer
        ..writeUint16(value.style)
        ..writeFloat32(value.x)
        ..writeFloat32(value.y)
        ..writeFloat32(value.scale);
    case PsdPrintFlagsInfo():
      writer
        ..writeUint16(value.version)
        ..writeUint8(value.centerCropMarks ? 1 : 0)
        ..writeUint8(value.reserved)
        ..writeUint32(value.bleedWidth)
        ..writeUint16(value.bleedScale);
    case PsdVersionInfo():
      writer
        ..writeUint32(value.version)
        ..writeUint8(value.hasRealMergedData ? 1 : 0);
      _writeUnicodeString(writer, value.writerName);
      _writeUnicodeString(writer, value.readerName);
      writer.writeUint32(value.fileVersion);
    case PsdUrlList():
      writer.writeUint32(value.items.length);
      for (final PsdUrlItem item in value.items) {
        writer
          ..writeUint32(item.number)
          ..writeUint32(item.id);
        _writeUnicodeString(writer, item.name);
      }
    case PsdDescriptorImageResource():
      writer
        ..writeUint32(value.descriptorVersion)
        ..writeBytes(PsdDescriptorCodec.encode(value.descriptor))
        ..writeBytes(value.trailingData);
    case PsdDisplayInfo():
      writer.writeUint32(value.version);
      for (final PsdAlphaChannelDisplay channel in value.channels) {
        if (channel.components.length != 4) {
          throw const PsdWriteException('Alpha-channel display records require four color components');
        }
        writer.writeUint16(channel.colorSpace);
        channel.components.forEach(writer.writeUint16);
        writer
          ..writeUint16(channel.opacity)
          ..writeUint8(channel.mode);
      }
    case PsdPathImageResource():
      writer.writeBytes(PsdVectorPathCodec.encode(value.path));
    case PsdSlicesResource():
      writer
        ..writeUint32(value.version)
        ..writeUint32(value.descriptorVersion)
        ..writeBytes(PsdDescriptorCodec.encode(value.descriptor))
        ..writeBytes(value.trailingData);
  }
}

/// Reads the optional ninth print flag after the eight historical flags.
PsdPrintFlags _readPrintFlags(PsdBinaryReader reader) {
  final List<bool> flags = <bool>[for (int index = 0; index < 8; index++) reader.readUint8() != 0];
  final bool? printFlags = reader.isAtEnd ? null : reader.readUint8() != 0;
  return PsdPrintFlags(
    labels: flags[0],
    cropMarks: flags[1],
    colorBars: flags[2],
    registrationMarks: flags[3],
    negative: flags[4],
    flip: flags[5],
    interpolate: flags[6],
    caption: flags[7],
    printFlags: printFlags,
  );
}

/// Reads fixed-size halftone records until the resource ends.
PsdHalftoneScreens _readHalftoneScreens(PsdBinaryReader reader, int resourceId) {
  if (reader.remaining % 18 != 0) {
    throw const PsdFormatException('Halftone-screen resource length is not divisible by 18');
  }
  final List<PsdHalftoneScreen> screens = <PsdHalftoneScreen>[];
  while (!reader.isAtEnd) {
    final double frequency = reader.readUint32() / 65536;
    final int unit = reader.readUint16();
    final double angle = reader.readInt32() / 65536;
    final int shape = reader.readUint16();
    reader.skip(4);
    screens.add(
      PsdHalftoneScreen(
        frequency: frequency,
        unit: unit,
        angle: angle,
        shape: shape,
        useAccurate: reader.readUint8() != 0,
        usePrinter: reader.readUint8() != 0,
      ),
    );
  }
  return PsdHalftoneScreens(resourceId: resourceId, screens: screens);
}

/// Reads fixed-size transfer functions until the resource ends.
PsdTransferFunctions _readTransferFunctions(PsdBinaryReader reader, int resourceId) {
  if (reader.remaining % 28 != 0) {
    throw const PsdFormatException('Transfer-function resource length is not divisible by 28');
  }
  final List<PsdTransferFunction> functions = <PsdTransferFunction>[];
  while (!reader.isAtEnd) {
    functions.add(
      PsdTransferFunction(
        curve: <int>[for (int index = 0; index < 13; index++) reader.readInt16()],
        override: reader.readUint16(),
      ),
    );
  }
  return PsdTransferFunctions(resourceId: resourceId, functions: functions);
}

/// Reads grid cycles followed by five-byte guide records.
PsdGridAndGuides _readGridAndGuides(PsdBinaryReader reader) {
  final int version = reader.readUint32();
  final int horizontal = reader.readUint32();
  final int vertical = reader.readUint32();
  final int count = reader.readUint32();
  if (count > reader.remaining ~/ 5) {
    throw const PsdFormatException('Truncated grid-and-guides resource');
  }
  return PsdGridAndGuides(
    version: version,
    horizontalCycle: horizontal,
    verticalCycle: vertical,
    guides: <PsdGuide>[for (int index = 0; index < count; index++) PsdGuide(location: reader.readUint32(), direction: reader.readUint8())],
  );
}

/// Reads a Photoshop 4 or later thumbnail header and payload.
PsdThumbnailResource _readThumbnail(PsdBinaryReader reader, int resourceId) {
  final int format = reader.readUint32();
  final int width = reader.readUint32();
  final int height = reader.readUint32();
  final int rowBytes = reader.readUint32();
  final int totalSize = reader.readUint32();
  final int size = reader.readUint32();
  final int bits = reader.readUint16();
  final int planes = reader.readUint16();
  return PsdThumbnailResource(
    resourceId: resourceId,
    format: format,
    width: width,
    height: height,
    rowBytes: rowBytes,
    totalSize: totalSize,
    bitsPerPixel: bits,
    planes: planes,
    data: reader.readBytes(size),
  );
}

/// Reads a count-prefixed URL list.
PsdUrlList _readUrlList(PsdBinaryReader reader) {
  final int count = reader.readUint32();
  final List<PsdUrlItem> items = <PsdUrlItem>[];
  for (int index = 0; index < count; index++) {
    items.add(PsdUrlItem(number: reader.readUint32(), id: reader.readUint32(), name: _readUnicodeString(reader)));
  }
  return PsdUrlList(items);
}

/// Reads Photoshop writer, reader, and merged-composite information.
PsdVersionInfo _readVersionInfo(PsdBinaryReader reader) => PsdVersionInfo(
  version: reader.readUint32(),
  hasRealMergedData: reader.readUint8() != 0,
  writerName: _readUnicodeString(reader),
  readerName: _readUnicodeString(reader),
  fileVersion: reader.readUint32(),
);

/// Reads the two-byte-counted selected-layer id list.
PsdIntegerListImageResource _readLayerSelectionIds(PsdBinaryReader reader) {
  final int count = reader.readUint16();
  if (count > reader.remaining ~/ 4) {
    throw const PsdFormatException('Truncated layer-selection id list');
  }
  return PsdIntegerListImageResource(
    resourceId: PsdImageResourceIds.layerSelectionIds,
    values: <int>[for (int index = 0; index < count; index++) reader.readUint32()],
    valueBytes: 4,
    layout: PsdImageResourceListLayout.uint16Count,
  );
}

/// Reads versioned alpha-channel display records.
PsdDisplayInfo _readDisplayInfo(PsdBinaryReader reader) {
  final int version = reader.readUint32();
  if (reader.remaining % 13 != 0) {
    throw const PsdFormatException('Display-info resource length is not divisible by 13');
  }
  final List<PsdAlphaChannelDisplay> channels = <PsdAlphaChannelDisplay>[];
  while (!reader.isAtEnd) {
    channels.add(
      PsdAlphaChannelDisplay(
        colorSpace: reader.readUint16(),
        components: <int>[for (int index = 0; index < 4; index++) reader.readUint16()],
        opacity: reader.readUint16(),
        mode: reader.readUint8(),
      ),
    );
  }
  return PsdDisplayInfo(version: version, channels: channels);
}

/// Reads a four-byte descriptor version followed by one action descriptor.
PsdDescriptorImageResource _readDescriptorResource(PsdBinaryReader reader, int resourceId) {
  final int version = reader.readUint32();
  final Uint8List descriptorBytes = reader.readView(reader.remaining);
  final ({PsdDescriptor descriptor, int bytesRead}) decoded = PsdDescriptorCodec.decodePrefix(descriptorBytes);
  return PsdDescriptorImageResource(
    resourceId: resourceId,
    descriptorVersion: version,
    descriptor: decoded.descriptor,
    trailingData: Uint8List.fromList(Uint8List.sublistView(descriptorBytes, decoded.bytesRead)),
  );
}

/// Reads modern descriptor-backed slices or retains legacy version 6 bytes.
PsdImageResourceData _readSlices(PsdBinaryReader reader) {
  final Uint8List bytes = reader.readBytes(reader.remaining);
  final PsdBinaryReader local = PsdBinaryReader(bytes);
  final int version = local.readUint32();
  if (version != 7 && version != 8) {
    return PsdBinaryMetadataResource(resourceId: PsdImageResourceIds.slices, data: bytes);
  }
  final int descriptorVersion = local.readUint32();
  final Uint8List descriptorBytes = local.readView(local.remaining);
  final ({PsdDescriptor descriptor, int bytesRead}) decoded = PsdDescriptorCodec.decodePrefix(descriptorBytes);
  return PsdSlicesResource(
    version: version,
    descriptorVersion: descriptorVersion,
    descriptor: decoded.descriptor,
    trailingData: Uint8List.fromList(Uint8List.sublistView(descriptorBytes, decoded.bytesRead)),
  );
}

/// Reads uncounted unsigned integers of [bytesPerValue].
List<int> _readUnsignedIntegers(PsdBinaryReader reader, int bytesPerValue) {
  if (reader.remaining % bytesPerValue != 0) {
    throw PsdFormatException('Integer-list length is not divisible by $bytesPerValue');
  }
  final List<int> result = <int>[];
  while (!reader.isAtEnd) {
    result.add(bytesPerValue == 2 ? reader.readUint16() : reader.readUint32());
  }
  return result;
}

/// Writes a counted or uncounted fixed-width integer list.
void _writeIntegerList(PsdBinaryWriter writer, PsdIntegerListImageResource value) {
  switch (value.layout) {
    case PsdImageResourceListLayout.uncounted:
      break;
    case PsdImageResourceListLayout.uint16Count:
      _requireUnsigned(value.values.length, 16, 'image-resource list count');
      writer.writeUint16(value.values.length);
    case PsdImageResourceListLayout.uint32Count:
      writer.writeUint32(value.values.length);
  }
  for (final int item in value.values) {
    if (value.valueBytes == 2) {
      _requireUnsigned(item, 16, 'image-resource list item');
      writer.writeUint16(item);
    } else if (value.valueBytes == 4) {
      _requireUnsigned(item, 32, 'image-resource list item');
      writer.writeUint32(item);
    } else {
      throw const PsdWriteException('Image-resource integer lists require two-byte or four-byte values');
    }
  }
}

/// Reads Pascal strings until the resource ends.
List<String> _readPascalStrings(PsdBinaryReader reader) {
  final List<String> result = <String>[];
  while (!reader.isAtEnd) {
    result.add(reader.readString(reader.readUint8()));
  }
  return result;
}

/// Writes one unpadded one-byte Pascal string.
void _writePascalString(PsdBinaryWriter writer, String value) {
  final List<int> bytes = _oneByteString(value, 255);
  writer
    ..writeUint8(bytes.length)
    ..writeBytes(bytes);
}

/// Reads UTF-16 strings until the resource ends.
List<String> _readUnicodeStrings(PsdBinaryReader reader) {
  final List<String> result = <String>[];
  while (!reader.isAtEnd) {
    result.add(_readUnicodeString(reader));
  }
  return result;
}

/// Reads a length-prefixed big-endian UTF-16 string.
String _readUnicodeString(PsdBinaryReader reader) {
  final int length = reader.readUint32();
  if (length > reader.remaining ~/ 2) {
    throw const PsdFormatException('Truncated image-resource Unicode string');
  }
  return String.fromCharCodes(<int>[for (int index = 0; index < length; index++) reader.readUint16()]);
}

/// Writes a length-prefixed big-endian UTF-16 string.
void _writeUnicodeString(PsdBinaryWriter writer, String value) {
  writer.writeUint32(value.codeUnits.length);
  value.codeUnits.forEach(writer.writeUint16);
}

/// Converts [value] to one-byte characters, rejecting unsupported code units.
List<int> _oneByteString(String value, int maximumLength) {
  if (value.length > maximumLength || value.codeUnits.any((unit) => unit > 0xff)) {
    throw PsdWriteException('Image-resource string must contain at most $maximumLength one-byte characters');
  }
  return value.codeUnits;
}

/// Reads a four-character ASCII signature at [offset], when available.
String? _asciiAt(Uint8List bytes, int offset) => offset < 0 || offset + 4 > bytes.length ? null : String.fromCharCodes(Uint8List.sublistView(bytes, offset, offset + 4));

/// Validates that [value] fits an unsigned integer of [bits].
void _requireUnsigned(int value, int bits, String label) {
  final int maximum = (BigInt.one << bits).toInt() - 1;
  if (value < 0 || value > maximum) {
    throw PsdWriteException('$label $value does not fit in $bits bits');
  }
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
