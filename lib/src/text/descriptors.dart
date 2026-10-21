part of '../text.dart';

/// Creates the action descriptor surrounding semantic text-engine data.
PsDescriptor _createTextDescriptor(
  PsdTextContent content, {
  required PsdTextDescriptorBounds? descriptorBounds,
  required PsdTextDescriptorBounds? boundingBox,
  required int textIndex,
}) {
  final String text = content.text.replaceAll('\r\n', '\r').replaceAll('\n', '\r');
  return PsDescriptor(
    name: '',
    classId: 'TxLr',
    items: <PsDescriptorItem>[
      PsDescriptorItem(
        key: 'Txt ',
        value: PsStringValue(value: '$text\u0000'),
      ),
      PsDescriptorItem(
        key: 'textGridding',
        value: PsEnumeratedValue(
          typeId: 'textGridding',
          value: content.gridding == PsdTextGridding.round ? 'Rnd ' : 'None',
        ),
      ),
      PsDescriptorItem(
        key: 'Ornt',
        value: PsEnumeratedValue(typeId: 'Ornt', value: content.orientation == PsdTextOrientation.vertical ? 'Vrtc' : 'Hrzn'),
      ),
      PsDescriptorItem(
        key: 'AntA',
        value: PsEnumeratedValue(
          typeId: 'Annt',
          value: _encodeDescriptorAntiAlias(content.antiAlias),
        ),
      ),
      if (descriptorBounds != null)
        PsDescriptorItem(
          key: 'bounds',
          value: _createBoundsValue(descriptorBounds),
        ),
      if (boundingBox != null)
        PsDescriptorItem(
          key: 'boundingBox',
          value: _createBoundsValue(boundingBox),
        ),
      PsDescriptorItem(
        key: 'TextIndex',
        value: PsIntegerValue(value: textIndex),
      ),
      PsDescriptorItem(
        key: 'EngineData',
        value: PsRawValue(value: PsdTextEngine.encode(content)),
      ),
    ],
  );
}

/// Creates a descriptor for common [warp] settings.
PsDescriptor _createWarpDescriptor(PsdTextWarp warp) => PsDescriptor(
  name: '',
  classId: 'warp',
  items: <PsDescriptorItem>[
    PsDescriptorItem(
      key: 'warpStyle',
      value: PsEnumeratedValue(
        typeId: 'warpStyle',
        value: _encodeWarpStyle(warp.style),
      ),
    ),
    PsDescriptorItem(
      key: 'warpValue',
      value: PsDoubleValue(value: warp.value),
    ),
    PsDescriptorItem(
      key: 'warpPerspective',
      value: PsDoubleValue(value: warp.perspective),
    ),
    PsDescriptorItem(
      key: 'warpPerspectiveOther',
      value: PsDoubleValue(value: warp.perspectiveOther),
    ),
    PsDescriptorItem(
      key: 'warpRotate',
      value: PsEnumeratedValue(
        typeId: 'Ornt',
        value: warp.rotation == PsdTextOrientation.vertical ? 'Vrtc' : 'Hrzn',
      ),
    ),
  ],
);

/// Creates a Photoshop bounds descriptor from [bounds].
PsObjectValue _createBoundsValue(PsdTextDescriptorBounds bounds) => PsObjectValue(
  value: PsDescriptor(
    name: '',
    classId: 'bounds',
    items: <PsDescriptorItem>[
      PsDescriptorItem(
        key: 'Left',
        value: PsUnitFloatValue(unit: bounds.left.unit, value: bounds.left.value),
      ),
      PsDescriptorItem(
        key: 'Top ',
        value: PsUnitFloatValue(unit: bounds.top.unit, value: bounds.top.value),
      ),
      PsDescriptorItem(
        key: 'Rght',
        value: PsUnitFloatValue(unit: bounds.right.unit, value: bounds.right.value),
      ),
      PsDescriptorItem(
        key: 'Btom',
        value: PsUnitFloatValue(unit: bounds.bottom.unit, value: bounds.bottom.value),
      ),
    ],
  ),
);

/// Decodes descriptor bounds while retaining each edge's unit.
PsdTextDescriptorBounds? _readDescriptorBounds(PsDescriptorValue? value) {
  final PsDescriptor? descriptor = switch (value) {
    PsObjectValue(:final PsDescriptor value) => value,
    _ => null,
  };
  if (descriptor == null) {
    return null;
  }

  /// Reads one unit-bearing edge.
  PsdTextUnitValue? edge(String key) => switch (descriptor.value(key)) {
    PsUnitFloatValue(:final String unit, :final double value) => PsdTextUnitValue(unit: unit, value: value),
    _ => null,
  };

  final PsdTextUnitValue? left = edge('Left');
  final PsdTextUnitValue? top = edge('Top ');
  final PsdTextUnitValue? right = edge('Rght');
  final PsdTextUnitValue? bottom = edge('Btom');
  if (left == null || top == null || right == null || bottom == null) {
    return null;
  }
  return PsdTextDescriptorBounds(
    left: left,
    top: top,
    right: right,
    bottom: bottom,
  );
}

/// Reads a numeric action-descriptor value.
double? _descriptorNumber(PsDescriptorValue? value) => switch (value) {
  PsDoubleValue(:final double value) => value,
  PsIntegerValue(:final int value) => value.toDouble(),
  final PsLargeIntegerValue integer => integer.asNumber()?.value,
  PsUnitFloatValue(:final double value) => value,
  _ => null,
};

/// Decodes common text-warp properties.
PsdTextWarp _readWarp(
  PsDescriptor descriptor, {
  required PsdTextOrientation fallbackRotation,
}) => PsdTextWarp(
  style: switch (descriptor.value('warpStyle')) {
    PsEnumeratedValue(:final String value) => _decodeWarpStyle(value),
    _ => PsdTextWarpStyle.none,
  },
  value: _descriptorNumber(descriptor.value('warpValue')) ?? 0,
  perspective: _descriptorNumber(descriptor.value('warpPerspective')) ?? 0,
  perspectiveOther: _descriptorNumber(descriptor.value('warpPerspectiveOther')) ?? 0,
  rotation: switch (descriptor.value('warpRotate')) {
    PsEnumeratedValue(:final String value) when value == 'Vrtc' => PsdTextOrientation.vertical,
    PsEnumeratedValue() => PsdTextOrientation.horizontal,
    _ => fallbackRotation,
  },
);

/// Updates common warp properties without dropping unknown descriptor keys.
PsDescriptor _updateWarpDescriptor(PsDescriptor descriptor, PsdTextWarp warp) => descriptor
    .withValue(
      'warpStyle',
      PsEnumeratedValue(
        typeId: 'warpStyle',
        value: _encodeWarpStyle(warp.style),
      ),
    )
    .withValue('warpValue', PsDoubleValue(value: warp.value))
    .withValue(
      'warpPerspective',
      PsDoubleValue(value: warp.perspective),
    )
    .withValue(
      'warpPerspectiveOther',
      PsDoubleValue(value: warp.perspectiveOther),
    )
    .withValue(
      'warpRotate',
      PsEnumeratedValue(
        typeId: 'Ornt',
        value: warp.rotation == PsdTextOrientation.vertical ? 'Vrtc' : 'Hrzn',
      ),
    );

/// Encodes a semantic warp style as an Adobe enumeration value.
String _encodeWarpStyle(PsdTextWarpStyle style) => switch (style) {
  PsdTextWarpStyle.none => 'warpNone',
  PsdTextWarpStyle.arc => 'warpArc',
  PsdTextWarpStyle.arcLower => 'warpArcLower',
  PsdTextWarpStyle.arcUpper => 'warpArcUpper',
  PsdTextWarpStyle.arch => 'warpArch',
  PsdTextWarpStyle.bulge => 'warpBulge',
  PsdTextWarpStyle.shellLower => 'warpShellLower',
  PsdTextWarpStyle.shellUpper => 'warpShellUpper',
  PsdTextWarpStyle.flag => 'warpFlag',
  PsdTextWarpStyle.wave => 'warpWave',
  PsdTextWarpStyle.fish => 'warpFish',
  PsdTextWarpStyle.rise => 'warpRise',
  PsdTextWarpStyle.fisheye => 'warpFisheye',
  PsdTextWarpStyle.inflate => 'warpInflate',
  PsdTextWarpStyle.squeeze => 'warpSqueeze',
  PsdTextWarpStyle.twist => 'warpTwist',
  PsdTextWarpStyle.cylinder => 'warpCylinder',
  PsdTextWarpStyle.custom => 'warpCustom',
};

/// Decodes an Adobe warp-style enumeration value.
PsdTextWarpStyle _decodeWarpStyle(String value) => switch (value) {
  'warpNone' => PsdTextWarpStyle.none,
  'warpArc' => PsdTextWarpStyle.arc,
  'warpArcLower' => PsdTextWarpStyle.arcLower,
  'warpArcUpper' => PsdTextWarpStyle.arcUpper,
  'warpArch' => PsdTextWarpStyle.arch,
  'warpBulge' => PsdTextWarpStyle.bulge,
  'warpShellLower' => PsdTextWarpStyle.shellLower,
  'warpShellUpper' => PsdTextWarpStyle.shellUpper,
  'warpFlag' => PsdTextWarpStyle.flag,
  'warpWave' => PsdTextWarpStyle.wave,
  'warpFish' => PsdTextWarpStyle.fish,
  'warpRise' => PsdTextWarpStyle.rise,
  'warpFisheye' => PsdTextWarpStyle.fisheye,
  'warpInflate' => PsdTextWarpStyle.inflate,
  'warpSqueeze' => PsdTextWarpStyle.squeeze,
  'warpTwist' => PsdTextWarpStyle.twist,
  'warpCylinder' => PsdTextWarpStyle.cylinder,
  'warpCustom' => PsdTextWarpStyle.custom,
  _ => PsdTextWarpStyle.custom,
};

/// Encodes an antialiasing mode for the surrounding action descriptor.
String _encodeDescriptorAntiAlias(PsdTextAntiAlias antiAlias) => switch (antiAlias) {
  PsdTextAntiAlias.none => 'Anno',
  PsdTextAntiAlias.sharp => 'antiAliasSharp',
  PsdTextAntiAlias.crisp => 'AnCr',
  PsdTextAntiAlias.strong => 'AnSt',
  PsdTextAntiAlias.smooth => 'AnSm',
  PsdTextAntiAlias.platform => 'antiAliasPlatformGray',
  PsdTextAntiAlias.platformLcd => 'antiAliasPlatformLCD',
};

/// Decodes an antialiasing mode from the surrounding action descriptor.
PsdTextAntiAlias? _tryDecodeDescriptorAntiAlias(PsDescriptorValue? value) {
  final String? encoded = switch (value) {
    PsEnumeratedValue(:final String value) => value,
    _ => null,
  };
  return switch (encoded) {
    'Anno' => PsdTextAntiAlias.none,
    'AnSh' || 'antiAliasSharp' => PsdTextAntiAlias.sharp,
    'AnCr' => PsdTextAntiAlias.crisp,
    'AnSt' => PsdTextAntiAlias.strong,
    'AnSm' => PsdTextAntiAlias.smooth,
    'antiAliasPlatformGray' => PsdTextAntiAlias.platform,
    'antiAliasPlatformLCD' => PsdTextAntiAlias.platformLcd,
    _ => null,
  };
}
