part of '../layer_options.dart';

/// Background fill Photoshop draws behind an artboard.
enum PsdArtboardBackground {
  /// Opaque white.
  white(1),

  /// Opaque black.
  black(2),

  /// No background.
  transparent(3),

  /// The color stored in the artboard descriptor.
  custom(4);

  /// Value stored under `artboardBackgroundType`.
  final int code;

  /// Creates a background stored as [code].
  const PsdArtboardBackground(this.code);

  /// Returns the background stored as [code], or `null` when unknown.
  static PsdArtboardBackground? fromCode(int? code) {
    for (final PsdArtboardBackground background in values) {
      if (background.code == code) {
        return background;
      }
    }
    return null;
  }
}

/// Artboard settings stored on a group layer's `artb` block.
final class PsdArtboard {
  /// Complete artboard descriptor, including properties not modeled here.
  final PsDescriptor descriptor;

  /// Creates a view over an `artboard` [descriptor].
  const PsdArtboard({required this.descriptor});

  /// Creates an artboard covering the given document-space edges.
  factory PsdArtboard.create({
    required double left,
    required double top,
    required double right,
    required double bottom,
    PsdArtboardBackground background = PsdArtboardBackground.white,
    PsColor? color,
    String presetName = '',
  }) {
    if (!(right > left && bottom > top)) {
      throw const PsWriteException(message: 'Artboard bounds must have a positive size');
    }
    return PsdArtboard(
      descriptor: PsDescriptor(
        name: '\u0000',
        classId: 'artboard',
        items: [
          PsDescriptorItem(
            key: 'artboardRect',
            value: PsObjectValue(
              value: PsDescriptor(
                name: '\u0000',
                classId: 'classFloatRect',
                items: [
                  PsDescriptorItem(
                    key: 'Top ',
                    value: PsDoubleValue(value: top),
                  ),
                  PsDescriptorItem(
                    key: 'Left',
                    value: PsDoubleValue(value: left),
                  ),
                  PsDescriptorItem(
                    key: 'Btom',
                    value: PsDoubleValue(value: bottom),
                  ),
                  PsDescriptorItem(
                    key: 'Rght',
                    value: PsDoubleValue(value: right),
                  ),
                ],
              ),
            ),
          ),
          const PsDescriptorItem(
            key: 'guideIndeces',
            value: PsListValue(values: []),
          ),
          PsDescriptorItem(
            key: 'artboardPresetName',
            value: PsStringValue(value: '$presetName\u0000'),
          ),
          PsDescriptorItem(
            key: 'Clr ',
            value: PsObjectValue(value: (color ?? PsColor.rgb(red: 255, green: 255, blue: 255)).descriptor),
          ),
          PsDescriptorItem(
            key: 'artboardBackgroundType',
            value: PsIntegerValue(value: background.code),
          ),
        ],
      ),
    );
  }

  /// Decodes an `artb` [block], returning `null` when it is malformed.
  static PsdArtboard? tryDecode(Uint8List data) {
    final PsDescriptor? descriptor = _tryDecodeVersioned(data);
    if (descriptor == null || descriptor.classId != 'artboard') {
      return null;
    }
    final PsdArtboard artboard = PsdArtboard(descriptor: descriptor);
    final double? left = artboard.left;
    final double? top = artboard.top;
    final double? right = artboard.right;
    final double? bottom = artboard.bottom;
    if (left == null || top == null || right == null || bottom == null || right <= left || bottom <= top) {
      return null;
    }
    return artboard;
  }

  /// Left edge in document pixels.
  double? get left => _rectangle?.scalarValue('Left');

  /// Top edge in document pixels.
  double? get top => _rectangle?.scalarValue('Top ');

  /// Right edge in document pixels.
  double? get right => _rectangle?.scalarValue('Rght');

  /// Bottom edge in document pixels.
  double? get bottom => _rectangle?.scalarValue('Btom');

  /// Background drawn behind the artboard, or `null` for an unknown type.
  PsdArtboardBackground? get background => PsdArtboardBackground.fromCode(descriptor.integerValue('artboardBackgroundType'));

  /// Stored background color, used when [background] is custom.
  PsColor? get color {
    final PsDescriptor? value = descriptor.objectValue('Clr ');
    return value == null ? null : PsColor.fromDescriptor(value);
  }

  /// Name of the device preset the artboard was created from, or empty.
  String get presetName => descriptor.stringValue('artboardPresetName') ?? '';

  /// Encodes this artboard as an `artb` block.
  PsdTaggedBlock toBlock() => PsdTaggedBlock(key: 'artb', data: encodePsdVersionedDescriptor(descriptor));

  /// Bounds descriptor stored under `artboardRect`.
  PsDescriptor? get _rectangle => descriptor.objectValue('artboardRect');
}

/// Document-wide artboard defaults stored in the `artd` block.
final class PsdArtboardDefaults {
  /// Complete descriptor, including properties not modeled here.
  final PsDescriptor descriptor;

  /// Creates a view over an `artd` [descriptor].
  const PsdArtboardDefaults({required this.descriptor});

  /// Creates Photoshop's defaults for a document holding [count] artboards.
  factory PsdArtboardDefaults.create({
    required int count,
    PsdArtboardBackground defaultBackground = PsdArtboardBackground.white,
    PsColor? defaultColor,
  }) {
    PsDescriptorValue origin() => PsObjectValue(value: PsPoint.create(horizontal: 0, vertical: 0).descriptor);
    return PsdArtboardDefaults(
      descriptor: PsDescriptor(
        name: '\u0000',
        classId: 'null',
        items: [
          PsDescriptorItem(
            key: 'Cnt ',
            value: PsIntegerValue(value: count),
          ),
          PsDescriptorItem(key: 'autoExpandOffset', value: origin()),
          PsDescriptorItem(key: 'origin', value: origin()),
          const PsDescriptorItem(key: 'autoExpandEnabled', value: PsBooleanValue(value: true)),
          const PsDescriptorItem(key: 'autoNestEnabled', value: PsBooleanValue(value: true)),
          const PsDescriptorItem(key: 'autoPositionEnabled', value: PsBooleanValue(value: true)),
          const PsDescriptorItem(key: 'shrinkwrapOnSaveEnabled', value: PsBooleanValue(value: true)),
          PsDescriptorItem(
            key: 'docDefaultNewArtboardBackgroundColor',
            value: PsObjectValue(value: (defaultColor ?? PsColor.rgb(red: 255, green: 255, blue: 255)).descriptor),
          ),
          PsDescriptorItem(
            key: 'docDefaultNewArtboardBackgroundType',
            value: PsIntegerValue(value: defaultBackground.code),
          ),
        ],
      ),
    );
  }

  /// Decodes an `artd` block payload, returning `null` when it is malformed.
  static PsdArtboardDefaults? tryDecode(Uint8List data) {
    final PsDescriptor? descriptor = _tryDecodeVersioned(data);
    return descriptor == null ? null : PsdArtboardDefaults(descriptor: descriptor);
  }

  /// Number of artboards Photoshop recorded in the document.
  int? get count => descriptor.integerValue('Cnt ');

  /// Whether artboards grow automatically around their content.
  bool? get autoExpandEnabled => descriptor.booleanValue('autoExpandEnabled');

  /// Whether layers nest automatically into the artboard they are moved onto.
  bool? get autoNestEnabled => descriptor.booleanValue('autoNestEnabled');

  /// Whether new artboards are positioned automatically.
  bool? get autoPositionEnabled => descriptor.booleanValue('autoPositionEnabled');

  /// Whether the canvas shrinks to fit the artboards when saving.
  bool? get shrinkwrapOnSaveEnabled => descriptor.booleanValue('shrinkwrapOnSaveEnabled');

  /// Background given to new artboards, or `null` for an unknown type.
  PsdArtboardBackground? get defaultBackground => PsdArtboardBackground.fromCode(descriptor.integerValue('docDefaultNewArtboardBackgroundType'));

  /// Custom background color given to new artboards.
  PsColor? get defaultColor {
    final PsDescriptor? value = descriptor.objectValue('docDefaultNewArtboardBackgroundColor');
    return value == null ? null : PsColor.fromDescriptor(value);
  }

  /// Encodes these defaults as an `artd` block.
  PsdTaggedBlock toBlock() => PsdTaggedBlock(key: 'artd', data: encodePsdVersionedDescriptor(descriptor));
}

/// Decodes a version 16 descriptor followed only by zero padding.
PsDescriptor? _tryDecodeVersioned(Uint8List data) {
  try {
    return decodePsdVersionedDescriptor(data);
  } on FormatException {
    return null;
  }
}
