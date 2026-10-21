part of '../layer_comps.dart';

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
    return PsBlendRange.create(
      channel: channel,
      sourceBlackLow: sourceBlack,
      sourceBlackHigh: sourceBlackSplit,
      sourceWhiteLow: sourceWhiteSplit,
      sourceWhiteHigh: sourceWhite,
      destinationBlackLow: destinationBlack,
      destinationBlackHigh: destinationBlackSplit,
      destinationWhiteLow: destinationWhiteSplit,
      destinationWhiteHigh: destinationWhite,
    ).descriptor;
  }

  /// Decodes one Blend If range, returning `null` for malformed descriptors.
  static PsdLayerCompBlendRange? tryFromDescriptor(PsDescriptor descriptor) {
    final PsBlendRange range = PsBlendRange.fromDescriptor(descriptor);
    final String? channel = _channelIdentifier(descriptor.value('Chnl'));
    final int? sourceBlack = range.sourceBlackLow;
    final int? sourceBlackSplit = range.sourceBlackHigh;
    final int? sourceWhiteSplit = range.sourceWhiteLow;
    final int? sourceWhite = range.sourceWhiteHigh;
    final int? destinationBlack = range.destinationBlackLow;
    final int? destinationBlackSplit = range.destinationBlackHigh;
    final int? destinationWhiteSplit = range.destinationWhiteLow;
    final int? destinationWhite = range.destinationWhiteHigh;
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
