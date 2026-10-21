part of '../layer_comps.dart';

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
