part of '../image_resources.dart';

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
  centered(code: 0),

  /// Scales the image to fit the page.
  sizeToFit(code: 1),

  /// Uses explicit position and scale values.
  userDefined(code: 2);

  /// Stored two-byte style code.
  final int code;

  /// Creates a style from its stored [code].
  const PsdPrintScaleStyle({required this.code});
}

/// Direction of a Photoshop guide.
enum PsdGuideDirection {
  /// Vertical guide.
  vertical(code: 0),

  /// Horizontal guide.
  horizontal(code: 1);

  /// Stored one-byte direction code.
  final int code;

  /// Creates a guide direction from its [code].
  const PsdGuideDirection({required this.code});
}
