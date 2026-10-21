part of '../smart_objects.dart';

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

  /// Photoshop smart-filter stack attached to this placed layer, when present.
  PsdSmartFilterStack? get smartFilters {
    final PsDescriptor? value = descriptor.objectValue('filterFX');
    return value == null ? null : PsdSmartFilterStack.fromDescriptor(value);
  }

  /// Instance identity associating this placement with an `FEid` pixel cache.
  ///
  /// Unlike [linkedResourceId], this must differ between instances sharing one
  /// source when their filter masks or projected previews differ.
  String? get placementId {
    final String? value = descriptor.stringValue('placed');
    return value != null && value.endsWith('\u0000') ? value.substring(0, value.length - 1) : value;
  }

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

  /// Returns a copy whose editable smart-filter metadata is [value].
  PsdDescriptorSmartObject withSmartFilters(PsdSmartFilterStack value) => withProperty(
    'filterFX',
    PsObjectValue(value: value.descriptor),
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

/// Converts a descriptor list of eight doubles to a placed transform.
PsdPlacedTransform? _transformFromValue(PsDescriptorValue? value) {
  if (value is! PsListValue || value.values.length != 8 || value.values.any((item) => item is! PsDoubleValue)) {
    return null;
  }
  return PsdPlacedTransform.fromList(
    values: <double>[for (final PsDescriptorValue item in value.values) (item as PsDoubleValue).value],
  );
}
