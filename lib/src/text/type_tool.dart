part of '../text.dart';

/// Editable contents of a Photoshop `TySh` tagged block.
final class PsdTypeTool {
  /// Type-tool structure version, normally 1.
  final int version;

  /// Transform from text coordinates into layer coordinates.
  final PsdTextTransform transform;

  /// Text record version, normally 50.
  final int textVersion;

  /// Action-descriptor version for [textDescriptor], normally 16.
  final int textDescriptorVersion;

  /// Descriptor containing text, orientation, antialiasing, and engine data.
  final PsDescriptor textDescriptor;

  /// Warp record version, normally 1.
  final int warpVersion;

  /// Action-descriptor version for [warpDescriptor], normally 16.
  final int warpDescriptorVersion;

  /// Descriptor containing text warp settings.
  final PsDescriptor warpDescriptor;

  /// Legacy single-precision bounds stored after the two descriptors.
  ///
  /// These are independent from the text-engine point or box geometry and the
  /// unit-bearing bounds inside [textDescriptor].
  final PsdTextBounds bounds;

  /// Bytes from newer Photoshop versions that follow the documented bounds.
  final Uint8List trailingData;

  /// Creates editable type-tool data.
  PsdTypeTool({
    required this.textDescriptor,
    required this.warpDescriptor,
    this.version = 1,
    this.transform = PsdTextTransform.identity,
    this.textVersion = 50,
    this.textDescriptorVersion = 16,
    this.warpVersion = 1,
    this.warpDescriptorVersion = 16,
    this.bounds = PsdTextBounds.zero,
    Uint8List? trailingData,
  }) : trailingData = trailingData ?? Uint8List(0);

  /// Creates a complete editable type-tool record from semantic [content].
  factory PsdTypeTool.fromText({
    required PsdTextContent content,
    PsdTextTransform transform = PsdTextTransform.identity,
    PsdTextBounds bounds = PsdTextBounds.zero,
    PsdTextDescriptorBounds? descriptorBounds,
    PsdTextDescriptorBounds? boundingBox,
    PsdTextWarp? warp,
    int textIndex = 0,
  }) => PsdTypeTool(
    transform: transform,
    bounds: bounds,
    textDescriptor: _createTextDescriptor(
      content,
      descriptorBounds: descriptorBounds,
      boundingBox: boundingBox,
      textIndex: textIndex,
    ),
    warpDescriptor: _createWarpDescriptor(
      warp ??
          PsdTextWarp(
            style: PsdTextWarpStyle.none,
            value: 0,
            perspective: 0,
            perspectiveOther: 0,
            rotation: content.orientation,
          ),
    ),
  );

  /// Plain Unicode text stored under the `Txt ` descriptor key.
  String get text => switch (textDescriptor.value('Txt ')) {
    PsStringValue(:final String value) => _withoutTerminalNull(value),
    _ => '',
  };

  /// Layout direction stored by the type-tool descriptor.
  PsdTextOrientation get orientation => switch (textDescriptor.value('Ornt')) {
    PsEnumeratedValue(:final String value) when value == 'Vrtc' => PsdTextOrientation.vertical,
    _ => PsdTextOrientation.horizontal,
  };

  /// Pixel-grid behavior stored by the type-tool descriptor.
  PsdTextGridding get gridding => switch (textDescriptor.value('textGridding')) {
    PsEnumeratedValue(:final String value) when value == 'Rnd ' => PsdTextGridding.round,
    _ => PsdTextGridding.none,
  };

  /// Antialiasing mode stored by the type-tool descriptor.
  PsdTextAntiAlias get antiAlias => _tryDecodeDescriptorAntiAlias(textDescriptor.value('AntA')) ?? PsdTextAntiAlias.sharp;

  /// Optional layout bounds from the text descriptor.
  PsdTextDescriptorBounds? get descriptorBounds => _readDescriptorBounds(textDescriptor.value('bounds'));

  /// Optional rendered bounding box from the text descriptor.
  PsdTextDescriptorBounds? get boundingBox => _readDescriptorBounds(textDescriptor.value('boundingBox'));

  /// Photoshop text object index.
  int get textIndex => switch (textDescriptor.value('TextIndex')) {
    PsIntegerValue(:final int value) => value,
    _ => 0,
  };

  /// Common warp properties decoded from [warpDescriptor].
  PsdTextWarp get warp => _readWarp(warpDescriptor, fallbackRotation: orientation);

  /// Semantic text, styles, and paragraphs suitable for application models.
  PsdTextContent get content {
    final PsdTextAntiAlias? descriptorAntiAlias = _tryDecodeDescriptorAntiAlias(
      textDescriptor.value('AntA'),
    );
    return PsdTextEngine.decode(
      engineData,
      fallbackText: text,
      orientation: orientation,
      fallbackAntiAlias: descriptorAntiAlias ?? PsdTextAntiAlias.sharp,
      antiAliasOverride: descriptorAntiAlias,
      gridding: gridding,
    );
  }

  /// Raw Adobe text-engine program stored under `EngineData`.
  Uint8List? get engineData => switch (textDescriptor.value('EngineData')) {
    PsRawValue(:final Uint8List value) => value,
    _ => null,
  };

  /// Returns a copy containing [text] in both descriptor text fields.
  PsdTypeTool withText(String text) {
    final String normalized = text.replaceAll('\r\n', '\r').replaceAll('\n', '\r');
    PsDescriptor descriptor = textDescriptor.withValue('Txt ', PsStringValue(value: '$normalized\u0000'));
    final Uint8List? engine = engineData;
    if (engine != null) {
      descriptor = descriptor.withValue('EngineData', PsRawValue(value: PsdTextEngine.replaceText(engine, normalized)));
    }
    return PsdTypeTool(
      version: version,
      transform: transform,
      textVersion: textVersion,
      textDescriptorVersion: textDescriptorVersion,
      textDescriptor: descriptor,
      warpVersion: warpVersion,
      warpDescriptorVersion: warpDescriptorVersion,
      warpDescriptor: warpDescriptor,
      bounds: bounds,
      trailingData: trailingData,
    );
  }

  /// Returns a semantic rewrite of this type tool using [content].
  ///
  /// Unlike [withText], this regenerates `EngineData`; use it when styles or
  /// paragraph properties changed and retain the original instance otherwise.
  PsdTypeTool withContent(PsdTextContent content) {
    final PsDescriptor descriptor = textDescriptor
        .withValue('Txt ', PsStringValue(value: '${content.text.replaceAll('\r\n', '\r').replaceAll('\n', '\r')}\u0000'))
        .withValue(
          'textGridding',
          PsEnumeratedValue(
            typeId: 'textGridding',
            value: content.gridding == PsdTextGridding.round ? 'Rnd ' : 'None',
          ),
        )
        .withValue(
          'Ornt',
          PsEnumeratedValue(typeId: 'Ornt', value: content.orientation == PsdTextOrientation.vertical ? 'Vrtc' : 'Hrzn'),
        )
        .withValue(
          'AntA',
          PsEnumeratedValue(typeId: 'Annt', value: _encodeDescriptorAntiAlias(content.antiAlias)),
        )
        .withValue('EngineData', PsRawValue(value: PsdTextEngine.encode(content)));
    final PsDescriptor warp = warpDescriptor.withValue(
      'warpRotate',
      PsEnumeratedValue(typeId: 'Ornt', value: content.orientation == PsdTextOrientation.vertical ? 'Vrtc' : 'Hrzn'),
    );
    return PsdTypeTool(
      version: version,
      transform: transform,
      textVersion: textVersion,
      textDescriptorVersion: textDescriptorVersion,
      textDescriptor: descriptor,
      warpVersion: warpVersion,
      warpDescriptorVersion: warpDescriptorVersion,
      warpDescriptor: warp,
      bounds: bounds,
      trailingData: trailingData,
    );
  }

  /// Returns a copy with common warp properties updated.
  ///
  /// Unknown custom-warp descriptor keys are retained.
  PsdTypeTool withWarp(PsdTextWarp warp) => PsdTypeTool(
    version: version,
    transform: transform,
    textVersion: textVersion,
    textDescriptorVersion: textDescriptorVersion,
    textDescriptor: textDescriptor,
    warpVersion: warpVersion,
    warpDescriptorVersion: warpDescriptorVersion,
    warpDescriptor: _updateWarpDescriptor(warpDescriptor, warp),
    bounds: bounds,
    trailingData: trailingData,
  );
}

/// Encodes and decodes the documented `TySh` structure.
abstract final class PsdTypeToolCodec {
  /// Decodes [bytes], returning `null` for malformed or unsupported data.
  static PsdTypeTool? tryDecode(Uint8List bytes) {
    try {
      return decode(bytes);
    } on FormatException {
      return null;
    }
  }

  /// Decodes one complete `TySh` tagged-block payload.
  static PsdTypeTool decode(Uint8List bytes) {
    final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
    final int version = reader.readUint16();
    final PsdTextTransform transform = PsdTextTransform(
      xx: reader.readFloat64(),
      xy: reader.readFloat64(),
      yx: reader.readFloat64(),
      yy: reader.readFloat64(),
      tx: reader.readFloat64(),
      ty: reader.readFloat64(),
    );
    final int textVersion = reader.readUint16();
    final int textDescriptorVersion = reader.readUint32();
    late final ({PsDescriptor descriptor, int bytesRead}) text;
    try {
      text = PsDescriptorCodec.decodePrefix(Uint8List.sublistView(reader.bytes, reader.offset));
    } on FormatException catch (error) {
      throw FormatException('Invalid TySh text descriptor: $error');
    }
    reader.skip(text.bytesRead);
    final int warpVersion = reader.readUint16();
    final int warpDescriptorVersion = reader.readUint32();
    late final ({PsDescriptor descriptor, int bytesRead}) warp;
    try {
      warp = PsDescriptorCodec.decodePrefix(Uint8List.sublistView(reader.bytes, reader.offset));
    } on FormatException catch (error) {
      throw FormatException('Invalid TySh warp descriptor: $error');
    }
    reader.skip(warp.bytesRead);
    final PsdTextBounds bounds = PsdTextBounds(
      left: reader.readFloat32(),
      top: reader.readFloat32(),
      right: reader.readFloat32(),
      bottom: reader.readFloat32(),
    );
    return PsdTypeTool(
      version: version,
      transform: transform,
      textVersion: textVersion,
      textDescriptorVersion: textDescriptorVersion,
      textDescriptor: text.descriptor,
      warpVersion: warpVersion,
      warpDescriptorVersion: warpDescriptorVersion,
      warpDescriptor: warp.descriptor,
      bounds: bounds,
      trailingData: reader.readBytes(reader.remaining),
    );
  }

  /// Encodes [typeTool] as a complete `TySh` payload.
  static Uint8List encode(PsdTypeTool typeTool) {
    final PsBinaryWriter writer = PsBinaryWriter()
      ..writeUint16(typeTool.version)
      ..writeFloat64(typeTool.transform.xx)
      ..writeFloat64(typeTool.transform.xy)
      ..writeFloat64(typeTool.transform.yx)
      ..writeFloat64(typeTool.transform.yy)
      ..writeFloat64(typeTool.transform.tx)
      ..writeFloat64(typeTool.transform.ty)
      ..writeUint16(typeTool.textVersion)
      ..writeUint32(typeTool.textDescriptorVersion)
      ..writeBytes(PsDescriptorCodec.encode(typeTool.textDescriptor))
      ..writeUint16(typeTool.warpVersion)
      ..writeUint32(typeTool.warpDescriptorVersion)
      ..writeBytes(PsDescriptorCodec.encode(typeTool.warpDescriptor))
      ..writeFloat32(typeTool.bounds.left)
      ..writeFloat32(typeTool.bounds.top)
      ..writeFloat32(typeTool.bounds.right)
      ..writeFloat32(typeTool.bounds.bottom)
      ..writeBytes(typeTool.trailingData);
    return writer.takeBytes();
  }
}
