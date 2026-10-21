part of '../adjustments.dart';

/// Reads a brightness/contrast payload, which on its own describes the legacy algorithm.
PsdBrightnessContrastAdjustment _readBrightnessContrast(PsBinaryReader reader) => PsdBrightnessContrastAdjustment(
  brightness: reader.readInt16(),
  contrast: reader.readInt16(),
  mean: reader.readInt16(),
  labColorOnly: reader.readUint8() != 0,
  useLegacy: true,
  trailingData: reader.readBytes(reader.remaining),
);

/// Reads main bitmap curves and optional version-4 duplicates.
PsdCurvesAdjustment _readCurves(PsBinaryReader reader) {
  if (reader.readUint8() != 0) {
    throw PsFormatException(message: 'Curves reserved byte must be zero', source: reader.bytes, offset: 0);
  }
  final int version = reader.readUint16();
  reader.readUint16();
  final int mask = reader.readUint16();
  final List<PsdCurve> curves = <PsdCurve>[];
  for (int channel = 0; channel < 16; channel++) {
    if (mask & (1 << channel) != 0) {
      curves.add(_readCurve(reader, channel));
    }
  }
  final List<PsdCurve> extended = <PsdCurve>[];
  if (reader.remaining >= 10 && _peekString(reader, 4) == 'Crv ') {
    reader.skip(4);
    reader.readUint16();
    final int count = reader.readUint32();
    for (int index = 0; index < count; index++) {
      extended.add(_readCurve(reader, reader.readUint16()));
    }
  }
  return PsdCurvesAdjustment(
    version: version,
    curves: curves,
    extendedCurves: extended,
    trailingData: reader.readBytes(reader.remaining),
  );
}

/// Reads one curve after its channel index has been determined.
PsdCurve _readCurve(PsBinaryReader reader, int channel) {
  final PsToneCurve curve = PsToneCurveCodec.read(reader);
  return PsdCurve(
    channel: channel,
    points: curve.points,
  );
}

/// Reads exposure floating-point values.
PsdExposureAdjustment _readExposure(PsBinaryReader reader) => PsdExposureAdjustment(
  version: reader.readUint16(),
  exposure: reader.readFloat32(),
  offset: reader.readFloat32(),
  gamma: reader.readFloat32(),
  trailingData: reader.readBytes(reader.remaining),
);

/// Reads the three tonal ranges of a color-balance adjustment.
PsdColorBalanceAdjustment _readColorBalance(PsBinaryReader reader) => PsdColorBalanceAdjustment(
  shadows: _readColorBalanceValues(reader),
  midtones: _readColorBalanceValues(reader),
  highlights: _readColorBalanceValues(reader),
  preserveLuminosity: reader.readUint8() != 0,
  trailingData: reader.readBytes(reader.remaining),
);

/// Reads one color-balance correction triplet.
PsdColorBalanceValues _readColorBalanceValues(PsBinaryReader reader) => PsdColorBalanceValues(
  cyanRed: reader.readInt16(),
  magentaGreen: reader.readInt16(),
  yellowBlue: reader.readInt16(),
);

/// Reads version-dependent photo-filter color data.
PsdPhotoFilterAdjustment _readPhotoFilter(PsBinaryReader reader) {
  final int version = reader.readUint16();
  final int colorLength = version == 3 ? 12 : 10;
  return PsdPhotoFilterAdjustment(
    version: version,
    colorData: reader.readBytes(colorLength),
    density: reader.readUint32(),
    preserveLuminosity: reader.readUint8() != 0,
    trailingData: reader.readBytes(reader.remaining),
  );
}

/// Reads posterize or threshold data.
PsdSingleValueAdjustment _readSingleValue(PsBinaryReader reader, String key) => PsdSingleValueAdjustment(
  type: key == 'post' ? PsdAdjustmentType.posterize : PsdAdjustmentType.threshold,
  value: reader.readUint16(),
  trailingData: reader.readBytes(reader.remaining),
);

/// Reads gradient-map settings, rejecting layouts other than the documented one.
PsdGradientMapAdjustment _readGradientMap(PsBinaryReader reader) {
  final int version = reader.readUint16();
  if (version != 1 && version != 3) {
    throw PsFormatException(message: 'Unsupported gradient map version $version', source: reader.bytes, offset: 0);
  }
  final bool reverse = reader.readUint8() != 0;
  final bool dither = reader.readUint8() != 0;
  final String? method = version == 3 ? reader.readString(4) : null;
  final int nameLength = reader.readUint32();
  if (nameLength > reader.remaining ~/ 2) {
    throw PsFormatException(message: 'Gradient map name length $nameLength exceeds the block', source: reader.bytes, offset: reader.offset - 4);
  }
  final List<int> name = [for (int index = 0; index < nameLength; index++) reader.readUint16()];
  if (name.isNotEmpty && name.last == 0) {
    name.removeLast();
  }
  final List<PsdGradientMapColorStop> colorStops = [
    for (int index = reader.readUint16(); index > 0; index--)
      PsdGradientMapColorStop(
        location: reader.readUint32(),
        midpoint: reader.readUint32(),
        colorSpace: reader.readUint16(),
        components: [for (int component = 0; component < 4; component++) reader.readUint16()],
        kind: reader.readUint16(),
      ),
  ];
  final List<PsdGradientMapOpacityStop> opacityStops = [
    for (int index = reader.readUint16(); index > 0; index--) PsdGradientMapOpacityStop(location: reader.readUint32(), midpoint: reader.readUint32(), opacity: reader.readUint16()),
  ];
  final int expansionCount = reader.readUint16();
  final int smoothness = reader.readUint16();
  final int expansionLength = reader.readUint16();
  if (expansionCount != 2 || expansionLength != 32) {
    throw PsFormatException(message: 'Unsupported gradient map expansion $expansionCount/$expansionLength', source: reader.bytes, offset: reader.offset);
  }
  return PsdGradientMapAdjustment(
    version: version,
    reverse: reverse,
    dither: dither,
    method: method,
    name: String.fromCharCodes(name),
    colorStops: colorStops,
    opacityStops: opacityStops,
    smoothness: smoothness,
    noise: reader.readUint16() != 0,
    randomSeed: reader.readUint32(),
    showsTransparency: reader.readUint16() != 0,
    restrictsColors: reader.readUint16() != 0,
    roughness: reader.readUint32(),
    colorModel: reader.readUint16(),
    minimumValues: [for (int index = 0; index < 4; index++) reader.readUint16()],
    maximumValues: [for (int index = 0; index < 4; index++) reader.readUint16()],
    trailingData: reader.readBytes(reader.remaining),
  );
}

/// Writes gradient-map settings.
void _writeGradientMap(PsBinaryWriter writer, PsdGradientMapAdjustment adjustment) {
  final String? method = adjustment.method;
  if ((adjustment.version == 3) != (method != null) || method != null && method.length != 4) {
    throw const PsWriteException(message: 'A version 3 gradient map needs a four-character method, and only version 3 stores one');
  }
  if (adjustment.colorStops.any((stop) => stop.components.length != 4) || adjustment.minimumValues.length != 4 || adjustment.maximumValues.length != 4) {
    throw const PsWriteException(message: 'Gradient map colours and noise ranges need four components');
  }
  writer
    ..writeUint16(adjustment.version)
    ..writeUint8(adjustment.reverse ? 1 : 0)
    ..writeUint8(adjustment.dither ? 1 : 0);
  if (method != null) {
    writer.writeString(method);
  }
  writer
    ..writeUint32(adjustment.name.length + 1)
    ..writeUint16List([...adjustment.name.codeUnits, 0])
    ..writeUint16(adjustment.colorStops.length);
  for (final PsdGradientMapColorStop stop in adjustment.colorStops) {
    writer
      ..writeUint32(stop.location)
      ..writeUint32(stop.midpoint)
      ..writeUint16(stop.colorSpace)
      ..writeUint16List(stop.components)
      ..writeUint16(stop.kind);
  }
  writer.writeUint16(adjustment.opacityStops.length);
  for (final PsdGradientMapOpacityStop stop in adjustment.opacityStops) {
    writer
      ..writeUint32(stop.location)
      ..writeUint32(stop.midpoint)
      ..writeUint16(stop.opacity);
  }
  writer
    ..writeUint16(2)
    ..writeUint16(adjustment.smoothness)
    ..writeUint16(32)
    ..writeUint16(adjustment.noise ? 1 : 0)
    ..writeUint32(adjustment.randomSeed)
    ..writeUint16(adjustment.showsTransparency ? 1 : 0)
    ..writeUint16(adjustment.restrictsColors ? 1 : 0)
    ..writeUint32(adjustment.roughness)
    ..writeUint16(adjustment.colorModel)
    ..writeUint16List(adjustment.minimumValues)
    ..writeUint16List(adjustment.maximumValues)
    ..writeBytes(adjustment.trailingData);
}

/// Reads a descriptor-backed fill or adjustment.
PsdDescriptorAdjustment _readDescriptorAdjustment(PsBinaryReader reader, String key) {
  int? version;
  if (key == 'clrL') {
    version = reader.readUint16();
  }
  final int descriptorVersion = reader.readUint32();
  final Uint8List payload = reader.readBytes(reader.remaining);
  final ({PsDescriptor descriptor, int bytesRead}) decoded = PsDescriptorCodec.decodePrefix(payload);
  return PsdDescriptorAdjustment(
    blockKey: key,
    type: _typeForKey(key),
    version: version,
    descriptorVersion: descriptorVersion,
    descriptor: decoded.descriptor,
    trailingData: Uint8List.fromList(Uint8List.sublistView(payload, decoded.bytesRead)),
  );
}

/// Writes bitmap curves and optional extended curves.
void _writeCurves(PsBinaryWriter writer, PsdCurvesAdjustment adjustment) {
  int mask = 0;
  for (final PsdCurve curve in adjustment.curves) {
    if (curve.channel < 0 || curve.channel > 15) {
      throw PsWriteException(message: 'Main curve channel ${curve.channel} must be from 0 through 15');
    }
    mask |= 1 << curve.channel;
  }
  writer
    ..writeUint8(0)
    ..writeUint16(adjustment.version)
    ..writeUint16(0)
    ..writeUint16(mask);
  final List<PsdCurve> ordered = <PsdCurve>[...adjustment.curves]..sort((left, right) => left.channel.compareTo(right.channel));
  for (final PsdCurve curve in ordered) {
    _writeCurve(writer, curve);
  }
  if (adjustment.extendedCurves.isNotEmpty) {
    writer
      ..writeString('Crv ')
      ..writeUint16(4)
      ..writeUint32(adjustment.extendedCurves.length);
    for (final PsdCurve curve in adjustment.extendedCurves) {
      writer.writeUint16(curve.channel);
      _writeCurve(writer, curve);
    }
  }
  writer.writeBytes(adjustment.trailingData);
}

/// Writes one curve without a channel prefix.
void _writeCurve(PsBinaryWriter writer, PsdCurve curve) {
  PsToneCurveCodec.write(writer, PsToneCurve(points: curve.points));
}

/// Writes the color-balance tonal ranges.
void _writeColorBalance(PsBinaryWriter writer, PsdColorBalanceAdjustment adjustment) {
  _writeColorBalanceValues(writer, adjustment.shadows);
  _writeColorBalanceValues(writer, adjustment.midtones);
  _writeColorBalanceValues(writer, adjustment.highlights);
  writer
    ..writeUint8(adjustment.preserveLuminosity ? 1 : 0)
    ..writeBytes(adjustment.trailingData);
}

/// Writes one color-balance correction triplet.
void _writeColorBalanceValues(PsBinaryWriter writer, PsdColorBalanceValues values) {
  writer
    ..writeInt16(values.cyanRed)
    ..writeInt16(values.magentaGreen)
    ..writeInt16(values.yellowBlue);
}

/// Writes version-dependent photo-filter data.
void _writePhotoFilter(PsBinaryWriter writer, PsdPhotoFilterAdjustment adjustment) {
  final int expectedLength = adjustment.version == 3 ? 12 : 10;
  if (adjustment.colorData.length != expectedLength) {
    throw PsWriteException(message: 'Photo filter version ${adjustment.version} requires $expectedLength color bytes');
  }
  writer
    ..writeUint16(adjustment.version)
    ..writeBytes(adjustment.colorData)
    ..writeUint32(adjustment.density)
    ..writeUint8(adjustment.preserveLuminosity ? 1 : 0)
    ..writeBytes(adjustment.trailingData);
}

/// Writes the version header and complete action descriptor.
void _writeDescriptorAdjustment(PsBinaryWriter writer, PsdDescriptorAdjustment adjustment) {
  if (adjustment.blockKey == 'clrL') {
    writer.writeUint16(adjustment.version ?? 1);
  }
  writer
    ..writeUint32(adjustment.descriptorVersion)
    ..writeBytes(PsDescriptorCodec.encode(adjustment.descriptor))
    ..writeBytes(adjustment.trailingData);
}

/// Peeks at [length] one-byte characters without advancing [reader].
String _peekString(PsBinaryReader reader, int length) => String.fromCharCodes(
  Uint8List.sublistView(reader.bytes, reader.offset, reader.offset + length),
);
