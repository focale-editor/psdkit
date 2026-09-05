import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:psdkit/src/effects.dart';
import 'package:psdkit/src/model.dart';

/// Maximum number of layer compositions accepted from untrusted metadata.
const int _maximumLayerComps = 10000;

/// Maximum unrelated entries accepted in one shared-metadata block.
const int _maximumExtraSharedMetadataEntries = 1024;

/// A finite point stored in Photoshop layer-composition metadata.
typedef PsdLayerCompPoint = ({double horizontal, double vertical});

/// One source-and-destination Blend If range captured by a composition.
final class PsdLayerCompBlendRange {
  /// Photoshop channel identifier such as `Gry `, `Rd  `, `Grn `, or `Bl  `.
  final String channel;

  /// Source shadow cutoff.
  final int sourceBlack;

  /// Source shadow transition endpoint.
  final int sourceBlackSplit;

  /// Source highlight transition start.
  final int sourceWhiteSplit;

  /// Source highlight cutoff.
  final int sourceWhite;

  /// Underlying shadow cutoff.
  final int destinationBlack;

  /// Underlying shadow transition endpoint.
  final int destinationBlackSplit;

  /// Underlying highlight transition start.
  final int destinationWhiteSplit;

  /// Underlying highlight cutoff.
  final int destinationWhite;

  /// Creates one eight-handle Blend If range.
  const PsdLayerCompBlendRange({
    required this.channel,
    required this.sourceBlack,
    required this.sourceBlackSplit,
    required this.sourceWhiteSplit,
    required this.sourceWhite,
    required this.destinationBlack,
    required this.destinationBlackSplit,
    required this.destinationWhiteSplit,
    required this.destinationWhite,
  });

  /// Whether every handle is ordered inside the byte range.
  bool get isValid =>
      channel.isNotEmpty &&
      _orderedBytes(
        sourceBlack,
        sourceBlackSplit,
        sourceWhiteSplit,
        sourceWhite,
      ) &&
      _orderedBytes(
        destinationBlack,
        destinationBlackSplit,
        destinationWhiteSplit,
        destinationWhite,
      );

  /// Whether both tonal gates leave every pixel unchanged.
  bool get isNeutral =>
      sourceBlack == 0 &&
      sourceBlackSplit == 0 &&
      sourceWhiteSplit == 255 &&
      sourceWhite == 255 &&
      destinationBlack == 0 &&
      destinationBlackSplit == 0 &&
      destinationWhiteSplit == 255 &&
      destinationWhite == 255;

  /// Creates Photoshop's action descriptor for this range.
  PsDescriptor toDescriptor() {
    if (!isValid) {
      throw const PsWriteException(
        message: 'Layer-comp Blend If handles must be ordered bytes',
      );
    }
    return PsDescriptor(
      name: '\u0000',
      classId: 'Blnd',
      items: [
        PsDescriptorItem(
          key: 'Chnl',
          value: PsReferenceValue(
            values: [
              PsEnumeratedReferenceValue(
                name: '',
                classId: 'Chnl',
                typeId: 'Chnl',
                value: channel,
              ),
            ],
          ),
        ),
        PsDescriptorItem(
          key: 'SrcB',
          value: PsIntegerValue(value: sourceBlack),
        ),
        PsDescriptorItem(
          key: 'Srcl',
          value: PsIntegerValue(value: sourceBlackSplit),
        ),
        PsDescriptorItem(
          key: 'SrcW',
          value: PsIntegerValue(value: sourceWhiteSplit),
        ),
        PsDescriptorItem(
          key: 'Srcm',
          value: PsIntegerValue(value: sourceWhite),
        ),
        PsDescriptorItem(
          key: 'DstB',
          value: PsIntegerValue(value: destinationBlack),
        ),
        PsDescriptorItem(
          key: 'Dstl',
          value: PsIntegerValue(value: destinationBlackSplit),
        ),
        PsDescriptorItem(
          key: 'DstW',
          value: PsIntegerValue(value: destinationWhiteSplit),
        ),
        PsDescriptorItem(
          key: 'Dstt',
          value: PsIntegerValue(value: destinationWhite),
        ),
      ],
    );
  }

  /// Decodes one Blend If range, returning `null` for malformed descriptors.
  static PsdLayerCompBlendRange? tryFromDescriptor(PsDescriptor descriptor) {
    final String? channel = _channelIdentifier(descriptor.value('Chnl'));
    final int? sourceBlack = _integer(descriptor.value('SrcB'));
    final int? sourceBlackSplit = _integer(descriptor.value('Srcl'));
    final int? sourceWhiteSplit = _integer(descriptor.value('SrcW'));
    final int? sourceWhite = _integer(descriptor.value('Srcm'));
    final int? destinationBlack = _integer(descriptor.value('DstB'));
    final int? destinationBlackSplit = _integer(descriptor.value('Dstl'));
    final int? destinationWhiteSplit = _integer(descriptor.value('DstW'));
    final int? destinationWhite = _integer(descriptor.value('Dstt'));
    if (channel == null ||
        sourceBlack == null ||
        sourceBlackSplit == null ||
        sourceWhiteSplit == null ||
        sourceWhite == null ||
        destinationBlack == null ||
        destinationBlackSplit == null ||
        destinationWhiteSplit == null ||
        destinationWhite == null) {
      return null;
    }
    final PsdLayerCompBlendRange result = PsdLayerCompBlendRange(
      channel: channel,
      sourceBlack: sourceBlack,
      sourceBlackSplit: sourceBlackSplit,
      sourceWhiteSplit: sourceWhiteSplit,
      sourceWhite: sourceWhite,
      destinationBlack: destinationBlack,
      destinationBlackSplit: destinationBlackSplit,
      destinationWhiteSplit: destinationWhiteSplit,
      destinationWhite: destinationWhite,
    );
    return result.isValid ? result : null;
  }
}

/// Editable blending properties captured for one layer composition.
final class PsdLayerCompBlendOptions {
  /// Complete Photoshop descriptor, including uninterpreted properties.
  final PsDescriptor descriptor;

  /// Creates a loss-preserving view over [descriptor].
  const PsdLayerCompBlendOptions({required this.descriptor});

  /// Creates common appearance properties and optional Blend If ranges.
  factory PsdLayerCompBlendOptions.create({
    double? opacityPercent,
    String? blendMode,
    double? fillOpacityPercent,
    List<PsdLayerCompBlendRange>? blendingRanges,
  }) {
    _validatePercentage(opacityPercent, 'Layer-comp opacity');
    _validatePercentage(fillOpacityPercent, 'Layer-comp fill opacity');
    if (blendMode != null && blendMode.isEmpty) {
      throw const PsWriteException(
        message: 'Layer-comp blend mode cannot be empty',
      );
    }
    if (blendingRanges != null && blendingRanges.any((range) => !range.isValid)) {
      throw const PsWriteException(
        message: 'Layer-comp Blend If range is invalid',
      );
    }
    return PsdLayerCompBlendOptions(
      descriptor: PsDescriptor(
        name: '\u0000',
        classId: 'null',
        items: [
          if (opacityPercent != null)
            PsDescriptorItem(
              key: 'Opct',
              value: PsUnitFloatValue(
                unit: '#Prc',
                value: opacityPercent,
              ),
            ),
          if (blendMode != null)
            PsDescriptorItem(
              key: 'Md  ',
              value: PsEnumeratedValue(
                typeId: 'BlnM',
                value: blendMode,
              ),
            ),
          if (blendingRanges != null)
            PsDescriptorItem(
              key: 'Blnd',
              value: PsListValue(
                values: [
                  for (final PsdLayerCompBlendRange range in blendingRanges) PsObjectValue(value: range.toDescriptor()),
                ],
              ),
            ),
          if (fillOpacityPercent != null)
            PsDescriptorItem(
              key: 'fillOpacity',
              value: PsUnitFloatValue(
                unit: '#Prc',
                value: fillOpacityPercent,
              ),
            ),
        ],
      ),
    );
  }

  /// Captured overall opacity as a percentage.
  double? get opacityPercent => _percentage(descriptor.value('Opct'));

  /// Captured action-descriptor blend-mode identifier.
  String? get blendMode => _enumerated(
    descriptor.value('Md  '),
    typeId: 'BlnM',
  );

  /// Captured fill opacity as a percentage.
  double? get fillOpacityPercent => _percentage(
    descriptor.value('fillOpacity'),
  );

  /// Whether a Blend If list is explicitly present.
  bool get hasBlendingRanges => descriptor.value('Blnd') != null;

  /// Captured Blend If ranges, or `null` when a present list is malformed.
  List<PsdLayerCompBlendRange>? get blendingRanges {
    final PsDescriptorValue? value = descriptor.value('Blnd');
    if (value == null) {
      return const [];
    }
    if (value is! PsListValue || value.values.length > 64) {
      return null;
    }
    final List<PsdLayerCompBlendRange> result = [];
    final Set<String> channels = {};
    for (final PsDescriptorValue item in value.values) {
      if (item is! PsObjectValue) {
        return null;
      }
      final PsdLayerCompBlendRange? range = PsdLayerCompBlendRange.tryFromDescriptor(item.value);
      if (range == null || !channels.add(range.channel)) {
        return null;
      }
      result.add(range);
    }
    return List.unmodifiable(result);
  }

  /// Captured clipped-layer blending switch, when present.
  bool? get blendClipped => _boolean(descriptor.value('blendClipped'));

  /// Captured interior-effects blending switch, when present.
  bool? get blendInterior => _boolean(descriptor.value('blendInterior'));

  /// Captured transparency-shapes-layer switch, when present.
  bool? get transparencyShapesLayer => _boolean(
    descriptor.value('transparencyShapesLayer'),
  );

  /// Captured knockout enumeration, when present.
  String? get knockout => _enumerated(
    descriptor.value('knockout'),
    typeId: 'knockout',
  );

  /// Captured channel restrictions, or `null` for a malformed present list.
  List<String>? get channelRestrictions {
    final PsDescriptorValue? value = descriptor.value('channelRestrictions');
    if (value == null) {
      return const [];
    }
    if (value is! PsListValue || value.values.length > 64) {
      return null;
    }
    final List<String> result = [];
    for (final PsDescriptorValue item in value.values) {
      final String? channel = _enumerated(item, typeId: 'Chnl');
      if (channel == null) {
        return null;
      }
      result.add(channel);
    }
    return List.unmodifiable(result);
  }
}

/// Captured values shared by one or more composition identifiers on a layer.
final class PsdLayerCompLayerState {
  /// Complete Photoshop state descriptor.
  final PsDescriptor descriptor;

  /// Creates a loss-preserving view over [descriptor].
  const PsdLayerCompLayerState({required this.descriptor});

  /// Creates one supported per-layer composition state.
  factory PsdLayerCompLayerState.create({
    required List<int> compIdentifiers,
    bool? visible,
    PsdLayerCompPoint? positionOffset,
    PsdLayerCompBlendOptions? blendOptions,
    PsdLayerEffects? layerEffects,
    PsdLayerCompPoint? effectsReferencePoint,
  }) {
    if (compIdentifiers.isEmpty || compIdentifiers.length > _maximumLayerComps || compIdentifiers.any((identifier) => !_isSigned32(identifier))) {
      throw const PsWriteException(
        message: 'Layer-comp state requires signed 32-bit identifiers',
      );
    }
    if (!_validPoint(positionOffset) || !_validPoint(effectsReferencePoint)) {
      throw const PsWriteException(
        message: 'Layer-comp state points must be finite',
      );
    }
    return PsdLayerCompLayerState(
      descriptor: PsDescriptor(
        name: '\u0000',
        classId: 'null',
        items: [
          if (visible != null)
            PsDescriptorItem(
              key: 'enab',
              value: PsBooleanValue(value: visible),
            ),
          if (positionOffset != null)
            PsDescriptorItem(
              key: 'Ofst',
              value: PsObjectValue(
                value: _pointDescriptor(positionOffset, integers: true),
              ),
            ),
          if (layerEffects != null)
            PsDescriptorItem(
              key: 'Lefx',
              value: PsObjectValue(value: layerEffects.descriptor),
            ),
          if (blendOptions != null)
            PsDescriptorItem(
              key: 'blendOptions',
              value: PsObjectValue(value: blendOptions.descriptor),
            ),
          if (effectsReferencePoint != null)
            PsDescriptorItem(
              key: 'FXRefPoint',
              value: PsObjectValue(
                value: _pointDescriptor(
                  effectsReferencePoint,
                  integers: false,
                ),
              ),
            ),
          PsDescriptorItem(
            key: 'compList',
            value: PsListValue(
              values: [
                for (final int identifier in compIdentifiers) PsIntegerValue(value: identifier),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Composition identifiers that use this state, including reserved id zero.
  List<int> get compIdentifiers {
    final PsDescriptorValue? value = descriptor.value('compList');
    if (value is! PsListValue || value.values.length > _maximumLayerComps) {
      return const [];
    }
    final List<int> result = [];
    for (final PsDescriptorValue item in value.values) {
      final int? identifier = _integer(item);
      if (identifier == null) {
        return const [];
      }
      result.add(identifier);
    }
    return List.unmodifiable(result);
  }

  /// Captured visibility, or `null` when inherited from the current layer.
  bool? get visible => _boolean(descriptor.value('enab'));

  /// Captured translation relative to the current layer position.
  PsdLayerCompPoint? get positionOffset => _point(descriptor.value('Ofst'));

  /// Captured blending properties, when present.
  PsdLayerCompBlendOptions? get blendOptions => switch (descriptor.value('blendOptions')) {
    PsObjectValue(:final PsDescriptor value) => PsdLayerCompBlendOptions(descriptor: value),
    _ => null,
  };

  /// Captured layer effects, when present.
  PsdLayerEffects? get layerEffects => switch (descriptor.value('Lefx')) {
    PsObjectValue(:final PsDescriptor value) => PsdLayerEffects(descriptor: value),
    _ => null,
  };

  /// Captured effects reference point, when present.
  PsdLayerCompPoint? get effectsReferencePoint => _point(
    descriptor.value('FXRefPoint'),
  );
}

/// Per-layer Photoshop composition metadata stored in one `cmls` entry.
final class PsdLayerCompLayerData {
  /// Complete Photoshop `cmls` descriptor.
  final PsDescriptor descriptor;

  /// Creates a loss-preserving view over [descriptor].
  const PsdLayerCompLayerData({required this.descriptor});

  /// Creates editable metadata for one PSD layer record.
  factory PsdLayerCompLayerData.create({
    required int layerIdentifier,
    required PsdLayerCompPoint originalEffectsReferencePoint,
    required List<PsdLayerCompLayerState> states,
  }) {
    if (!_isSigned32(layerIdentifier) || !_validPoint(originalEffectsReferencePoint) || states.length > _maximumLayerComps + 1) {
      throw const PsWriteException(
        message: 'Layer-comp layer metadata is outside supported limits',
      );
    }
    return PsdLayerCompLayerData(
      descriptor: PsDescriptor(
        name: '\u0000',
        classId: 'null',
        items: [
          PsDescriptorItem(
            key: 'origFXRefPoint',
            value: PsObjectValue(
              value: _pointDescriptor(
                originalEffectsReferencePoint,
                integers: false,
              ),
            ),
          ),
          PsDescriptorItem(
            key: 'LyrI',
            value: PsIntegerValue(value: layerIdentifier),
          ),
          PsDescriptorItem(
            key: 'layerSettings',
            value: PsListValue(
              values: [
                for (final PsdLayerCompLayerState state in states) PsObjectValue(value: state.descriptor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Signed PSD layer identifier associated with this metadata.
  int? get layerIdentifier => _integer(descriptor.value('LyrI'));

  /// Effects reference point of the current layer state.
  PsdLayerCompPoint? get originalEffectsReferencePoint => _point(
    descriptor.value('origFXRefPoint'),
  );

  /// Captured state groups in descriptor order.
  List<PsdLayerCompLayerState> get states {
    final PsDescriptorValue? value = descriptor.value('layerSettings');
    if (value is! PsListValue || value.values.length > _maximumLayerComps + 1) {
      return const [];
    }
    return List.unmodifiable([
      for (final PsDescriptorValue item in value.values)
        if (item is PsObjectValue) PsdLayerCompLayerState(descriptor: item.value),
    ]);
  }

  /// Last captured state indexed by every nonzero composition identifier.
  Map<int, PsdLayerCompLayerState> get statesByCompIdentifier {
    final Map<int, PsdLayerCompLayerState> result = {};
    for (final PsdLayerCompLayerState state in states) {
      for (final int identifier in state.compIdentifiers) {
        if (identifier != 0) {
          result[identifier] = state;
        }
      }
    }
    return Map.unmodifiable(result);
  }
}

/// Encodes and decodes per-layer Photoshop `shmd`/`cmls` metadata.
abstract final class PsdLayerCompsCodec {
  /// Decodes the last `cmls` entry on [layer], or `null` when unavailable.
  static PsdLayerCompLayerData? tryDecodeLayer(PsdLayer layer) {
    final PsdTaggedBlock? block = layer.taggedBlock('shmd');
    if (block == null) {
      return null;
    }
    try {
      final List<_SharedMetadataEntry> entries = _decodeSharedMetadata(
        block.data,
      );
      for (int index = entries.length - 1; index >= 0; index--) {
        final _SharedMetadataEntry entry = entries[index];
        if (entry.key != 'cmls') {
          continue;
        }
        final PsDescriptor descriptor = _decodeVersionedDescriptor(
          entry.data,
        );
        final PsdLayerCompLayerData result = PsdLayerCompLayerData(
          descriptor: descriptor,
        );
        if (result.layerIdentifier == null || result.originalEffectsReferencePoint == null || descriptor.value('layerSettings') is! PsListValue) {
          return null;
        }
        return result;
      }
    } on Object {
      return null;
    }
    return null;
  }

  /// Returns [layer] with its `cmls` entry replaced by [data].
  static PsdLayer withLayerData(
    PsdLayer layer,
    PsdLayerCompLayerData? data,
  ) {
    final PsdTaggedBlock? block = layer.taggedBlock('shmd');
    List<_SharedMetadataEntry> entries;
    if (block == null) {
      entries = [];
    } else {
      try {
        entries = _decodeSharedMetadata(block.data);
      } on Object {
        if (data == null) {
          return layer;
        }
        entries = [];
      }
    }
    final List<_SharedMetadataEntry> updated = [
      for (final _SharedMetadataEntry entry in entries)
        if (entry.key != 'cmls') entry,
      if (data != null)
        _SharedMetadataEntry(
          signature: '8BIM',
          key: 'cmls',
          copyOnSheetDuplication: false,
          data: _encodeVersionedDescriptor(data.descriptor),
        ),
    ];
    return _copyLayerWithBlock(
      layer,
      updated.isEmpty
          ? null
          : PsdTaggedBlock(
              key: 'shmd',
              data: _encodeSharedMetadata(updated),
            ),
      key: 'shmd',
    );
  }
}

/// Convenient layer-composition access on individual layer records.
extension PsdLayerLayerComps on PsdLayer {
  /// Decoded per-layer composition metadata, when present and valid.
  PsdLayerCompLayerData? get layerCompData => PsdLayerCompsCodec.tryDecodeLayer(this);

  /// Returns a layer whose per-layer composition metadata is [data].
  PsdLayer withLayerCompData(PsdLayerCompLayerData? data) => PsdLayerCompsCodec.withLayerData(this, data);
}

/// One entry inside Photoshop's `shmd` tagged block.
final class _SharedMetadataEntry {
  /// Four-byte vendor signature.
  final String signature;

  /// Four-byte metadata key.
  final String key;

  /// Whether Photoshop copies this metadata when duplicating the sheet.
  final bool copyOnSheetDuplication;

  /// Opaque entry payload without alignment padding.
  final Uint8List data;

  /// Creates one shared-metadata entry.
  const _SharedMetadataEntry({
    required this.signature,
    required this.key,
    required this.copyOnSheetDuplication,
    required this.data,
  });
}

/// Decodes a bounded Photoshop shared-metadata sequence.
List<_SharedMetadataEntry> _decodeSharedMetadata(Uint8List bytes) {
  final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
  final int count = reader.readUint32();
  if (count > _maximumLayerComps + _maximumExtraSharedMetadataEntries) {
    throw const PsFormatException(message: 'Too many shared metadata entries');
  }
  final List<_SharedMetadataEntry> entries = [];
  for (int index = 0; index < count; index++) {
    final String signature = reader.readString(4);
    final String key = reader.readString(4);
    final bool copyOnSheetDuplication = reader.readUint8() != 0;
    reader.skip(3);
    final int length = reader.readLength(
      wide: false,
      label: 'shared metadata',
    );
    entries.add(
      _SharedMetadataEntry(
        signature: signature,
        key: key,
        copyOnSheetDuplication: copyOnSheetDuplication,
        data: reader.readBytes(length),
      ),
    );
    if (length.isOdd) {
      reader.skip(1);
    }
  }
  if (!reader.isAtEnd && reader.readBytes(reader.remaining).any((byte) => byte != 0)) {
    throw const PsFormatException(
      message: 'Unexpected shared metadata bytes',
    );
  }
  return entries;
}

/// Encodes Photoshop shared metadata with even-sized entry padding.
Uint8List _encodeSharedMetadata(List<_SharedMetadataEntry> entries) {
  final PsBinaryWriter writer = PsBinaryWriter();
  writer.writeUint32(entries.length);
  for (final _SharedMetadataEntry entry in entries) {
    if (entry.signature.length != 4 || entry.key.length != 4) {
      throw const PsWriteException(
        message: 'Shared metadata signatures and keys must have four characters',
      );
    }
    writer
      ..writeString(entry.signature)
      ..writeString(entry.key)
      ..writeUint8(entry.copyOnSheetDuplication ? 1 : 0)
      ..writeZeros(3)
      ..writeUint32(entry.data.length)
      ..writeBytes(entry.data);
    if (entry.data.length.isOdd) {
      writer.writeUint8(0);
    }
  }
  return writer.takeBytes();
}

/// Decodes one version-16 descriptor with zero-only trailing padding.
PsDescriptor _decodeVersionedDescriptor(Uint8List bytes) {
  final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
  if (reader.readUint32() != 16) {
    throw const PsFormatException(
      message: 'Unsupported layer-composition descriptor version',
    );
  }
  final Uint8List payload = reader.readView(reader.remaining);
  final ({PsDescriptor descriptor, int bytesRead}) decoded = PsDescriptorCodec.decodePrefix(payload);
  if (payload.skip(decoded.bytesRead).any((byte) => byte != 0)) {
    throw const PsFormatException(
      message: 'Unexpected layer-composition descriptor bytes',
    );
  }
  return decoded.descriptor;
}

/// Encodes one version-16 descriptor with four-byte padding.
Uint8List _encodeVersionedDescriptor(PsDescriptor descriptor) {
  final PsBinaryWriter writer = PsBinaryWriter();
  writer
    ..writeUint32(16)
    ..writeBytes(PsDescriptorCodec.encode(descriptor))
    ..writeZeros((4 - writer.length % 4) % 4);
  return writer.takeBytes();
}

/// Returns a layer with one tagged-block key replaced or removed.
PsdLayer _copyLayerWithBlock(
  PsdLayer source,
  PsdTaggedBlock? replacement, {
  required String key,
}) => PsdLayer(
  rectangle: source.rectangle,
  name: source.name,
  channels: source.channels,
  blendMode: source.blendMode,
  opacity: source.opacity,
  clipping: source.clipping,
  flags: source.flags,
  mask: source.mask,
  blendingRanges: source.blendingRanges,
  additionalInfo: [
    for (final PsdTaggedBlock block in source.additionalInfo)
      if (block.key != key) block,
    ?replacement,
  ],
);

/// Builds a Photoshop point descriptor.
PsDescriptor _pointDescriptor(
  PsdLayerCompPoint point, {
  required bool integers,
}) => PsDescriptor(
  name: '\u0000',
  classId: 'null',
  items: [
    PsDescriptorItem(
      key: 'Hrzn',
      value: integers ? PsIntegerValue(value: point.horizontal.round()) : PsDoubleValue(value: point.horizontal),
    ),
    PsDescriptorItem(
      key: 'Vrtc',
      value: integers ? PsIntegerValue(value: point.vertical.round()) : PsDoubleValue(value: point.vertical),
    ),
  ],
);

/// Reads a finite point descriptor.
PsdLayerCompPoint? _point(PsDescriptorValue? value) {
  if (value is! PsObjectValue) {
    return null;
  }
  final double? horizontal = _number(value.value.value('Hrzn'));
  final double? vertical = _number(value.value.value('Vrtc'));
  return horizontal == null || vertical == null ? null : (horizontal: horizontal, vertical: vertical);
}

/// Reads the channel identifier from a Photoshop reference value.
String? _channelIdentifier(PsDescriptorValue? value) {
  if (value is! PsReferenceValue || value.values.length != 1) {
    return null;
  }
  return switch (value.values.single) {
    PsEnumeratedReferenceValue(
      classId: 'Chnl',
      typeId: 'Chnl',
      :final String value,
    ) =>
      value,
    _ => null,
  };
}

/// Reads a descriptor Boolean.
bool? _boolean(PsDescriptorValue? value) => switch (value) {
  PsBooleanValue(:final bool value) => value,
  _ => null,
};

/// Reads a finite descriptor number.
double? _number(PsDescriptorValue? value) {
  final double? result = switch (value) {
    PsIntegerValue(:final int value) => value.toDouble(),
    PsDoubleValue(:final double value) => value,
    PsUnitFloatValue(:final double value) => value,
    _ => null,
  };
  return result?.isFinite ?? false ? result : null;
}

/// Reads a signed descriptor integer.
int? _integer(PsDescriptorValue? value) => switch (value) {
  PsIntegerValue(:final int value) => value,
  _ => null,
};

/// Reads one enumeration with the expected type identifier.
String? _enumerated(PsDescriptorValue? value, {required String typeId}) => switch (value) {
  PsEnumeratedValue(typeId: final String actual, :final String value) when actual == typeId => value,
  _ => null,
};

/// Reads a finite percentage from a `#Prc` unit float.
double? _percentage(PsDescriptorValue? value) => switch (value) {
  PsUnitFloatValue(unit: '#Prc', :final double value) when value.isFinite && value >= 0 && value <= 100 => value,
  _ => null,
};

/// Validates one optional percentage before writing it.
void _validatePercentage(double? value, String label) {
  if (value != null && (!value.isFinite || value < 0 || value > 100)) {
    throw PsWriteException(message: '$label must be from 0 through 100');
  }
}

/// Whether the optional record point is absent or finite.
bool _validPoint(PsdLayerCompPoint? point) => point == null || point.horizontal.isFinite && point.vertical.isFinite;

/// Whether four values are ordered bytes.
bool _orderedBytes(int first, int second, int third, int fourth) => first >= 0 && first <= second && second <= third && third <= fourth && fourth <= 255;

/// Whether [value] fits Photoshop's signed descriptor integer.
bool _isSigned32(int value) => value >= -0x80000000 && value <= 0x7fffffff;
