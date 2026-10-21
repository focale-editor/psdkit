part of '../image_resources.dart';

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
PsdImageResourceData _readImageResource(PsBinaryReader reader, int resourceId) {
  if (PsdImageResourceIds.isPath(resourceId) || resourceId == PsdImageResourceIds.workingPath) {
    final Uint8List bytes = reader.readBytes(reader.remaining);
    return PsdPathImageResource(resourceId: resourceId, path: PsdVectorPathCodec.decode(bytes));
  }
  if (resourceId == PsdImageResourceIds.iccProfile) {
    return PsdIccProfileResource(data: reader.readBytes(reader.remaining));
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

/// Reads the optional ninth print flag after the eight historical flags.
PsdPrintFlags _readPrintFlags(PsBinaryReader reader) {
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
PsdHalftoneScreens _readHalftoneScreens(PsBinaryReader reader, int resourceId) {
  if (reader.remaining % 18 != 0) {
    throw const PsFormatException(message: 'Halftone-screen resource length is not divisible by 18');
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
PsdTransferFunctions _readTransferFunctions(PsBinaryReader reader, int resourceId) {
  if (reader.remaining % 28 != 0) {
    throw const PsFormatException(message: 'Transfer-function resource length is not divisible by 28');
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
PsdGridAndGuides _readGridAndGuides(PsBinaryReader reader) {
  final int version = reader.readUint32();
  final int horizontal = reader.readUint32();
  final int vertical = reader.readUint32();
  final int count = reader.readUint32();
  if (count > reader.remaining ~/ 5) {
    throw const PsFormatException(message: 'Truncated grid-and-guides resource');
  }
  return PsdGridAndGuides(
    version: version,
    horizontalCycle: horizontal,
    verticalCycle: vertical,
    guides: <PsdGuide>[for (int index = 0; index < count; index++) PsdGuide(location: reader.readUint32(), direction: reader.readUint8())],
  );
}

/// Reads a Photoshop 4 or later thumbnail header and payload.
PsdThumbnailResource _readThumbnail(PsBinaryReader reader, int resourceId) {
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
PsdUrlList _readUrlList(PsBinaryReader reader) {
  final int count = reader.readUint32();
  final List<PsdUrlItem> items = <PsdUrlItem>[];
  for (int index = 0; index < count; index++) {
    items.add(PsdUrlItem(number: reader.readUint32(), id: reader.readUint32(), name: _readUnicodeString(reader)));
  }
  return PsdUrlList(items: items);
}

/// Reads Photoshop writer, reader, and merged-composite information.
PsdVersionInfo _readVersionInfo(PsBinaryReader reader) => PsdVersionInfo(
  version: reader.readUint32(),
  hasRealMergedData: reader.readUint8() != 0,
  writerName: _readUnicodeString(reader),
  readerName: _readUnicodeString(reader),
  fileVersion: reader.readUint32(),
);

/// Reads the two-byte-counted selected-layer id list.
PsdIntegerListImageResource _readLayerSelectionIds(PsBinaryReader reader) {
  final int count = reader.readUint16();
  if (count > reader.remaining ~/ 4) {
    throw const PsFormatException(message: 'Truncated layer-selection id list');
  }
  return PsdIntegerListImageResource(
    resourceId: PsdImageResourceIds.layerSelectionIds,
    values: <int>[for (int index = 0; index < count; index++) reader.readUint32()],
    valueBytes: 4,
    layout: PsdImageResourceListLayout.uint16Count,
  );
}

/// Reads versioned alpha-channel display records.
PsdDisplayInfo _readDisplayInfo(PsBinaryReader reader) {
  final int version = reader.readUint32();
  if (reader.remaining % 13 != 0) {
    throw const PsFormatException(message: 'Display-info resource length is not divisible by 13');
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
PsdDescriptorImageResource _readDescriptorResource(PsBinaryReader reader, int resourceId) {
  final int version = reader.readUint32();
  final Uint8List descriptorBytes = reader.readView(reader.remaining);
  final ({PsDescriptor descriptor, int bytesRead}) decoded = PsDescriptorCodec.decodePrefix(descriptorBytes);
  return PsdDescriptorImageResource(
    resourceId: resourceId,
    descriptorVersion: version,
    descriptor: decoded.descriptor,
    trailingData: Uint8List.fromList(Uint8List.sublistView(descriptorBytes, decoded.bytesRead)),
  );
}

/// Reads modern descriptor-backed slices or retains legacy version 6 bytes.
PsdImageResourceData _readSlices(PsBinaryReader reader) {
  final Uint8List bytes = reader.readBytes(reader.remaining);
  final PsBinaryReader local = PsBinaryReader(bytes: bytes);
  final int version = local.readUint32();
  if (version != 7 && version != 8) {
    return PsdBinaryMetadataResource(resourceId: PsdImageResourceIds.slices, data: bytes);
  }
  final int descriptorVersion = local.readUint32();
  final Uint8List descriptorBytes = local.readView(local.remaining);
  final ({PsDescriptor descriptor, int bytesRead}) decoded = PsDescriptorCodec.decodePrefix(descriptorBytes);
  return PsdSlicesResource(
    version: version,
    descriptorVersion: descriptorVersion,
    descriptor: decoded.descriptor,
    trailingData: Uint8List.fromList(Uint8List.sublistView(descriptorBytes, decoded.bytesRead)),
  );
}

/// Reads uncounted unsigned integers of [bytesPerValue].
List<int> _readUnsignedIntegers(PsBinaryReader reader, int bytesPerValue) {
  if (reader.remaining % bytesPerValue != 0) {
    throw PsFormatException(message: 'Integer-list length is not divisible by $bytesPerValue');
  }
  final List<int> result = <int>[];
  while (!reader.isAtEnd) {
    result.add(bytesPerValue == 2 ? reader.readUint16() : reader.readUint32());
  }
  return result;
}
