part of '../smart_objects.dart';

/// One Photoshop smart filter stored inside a placed-layer descriptor.
///
/// The complete [descriptor] remains available so readers can round-trip
/// vendor-specific filter settings even when no semantic accessor exists.
final class PsdSmartFilter {
  /// Complete `filterFX` descriptor for this stack entry.
  final PsDescriptor descriptor;

  /// Creates a Photoshop-compatible smart-filter descriptor.
  factory PsdSmartFilter({
    required int filterId,
    required String name,
    required String blendMode,
    required double opacity,
    PsDescriptor? filter,
    bool enabled = true,
    bool hasOptions = true,
  }) {
    if (!opacity.isFinite || opacity < 0 || opacity > 1) {
      throw RangeError.range(opacity, 0, 1, 'opacity');
    }
    return PsdSmartFilter.fromDescriptor(
      PsDescriptor(
        name: '',
        classId: 'filterFX',
        items: [
          PsDescriptorItem(
            key: 'Nm  ',
            value: PsStringValue(value: name),
          ),
          PsDescriptorItem(
            key: 'blendOptions',
            value: PsObjectValue(
              value: PsDescriptor(
                name: '',
                classId: 'blendOptions',
                items: [
                  PsDescriptorItem(
                    key: 'Opct',
                    value: PsUnitFloatValue(
                      unit: '#Prc',
                      value: opacity * 100,
                    ),
                  ),
                  PsDescriptorItem(
                    key: 'Md  ',
                    value: PsEnumeratedValue(
                      typeId: 'BlnM',
                      value: blendMode,
                    ),
                  ),
                ],
              ),
            ),
          ),
          PsDescriptorItem(
            key: 'enab',
            value: PsBooleanValue(value: enabled),
          ),
          PsDescriptorItem(
            key: 'hasoptions',
            value: PsBooleanValue(value: hasOptions),
          ),
          const PsDescriptorItem(
            key: 'FrgC',
            value: PsObjectValue(value: _blackRgbDescriptor),
          ),
          const PsDescriptorItem(
            key: 'BckC',
            value: PsObjectValue(value: _blackRgbDescriptor),
          ),
          PsDescriptorItem(
            key: 'filterID',
            value: PsIntegerValue(value: filterId),
          ),
          if (filter != null)
            PsDescriptorItem(
              key: 'Fltr',
              value: PsObjectValue(value: filter),
            ),
        ],
      ),
    );
  }

  /// Wraps an existing Photoshop smart-filter [descriptor] losslessly.
  const PsdSmartFilter.fromDescriptor(this.descriptor);

  /// Numeric Photoshop filter identifier, when the entry exposes one.
  int? get filterId => descriptor.integerValue('filterID');

  /// Human-readable filter name, when present.
  String? get name => descriptor.stringValue('Nm  ', trimTerminalNulls: false);

  /// Action descriptor containing the filter-specific parameters.
  PsDescriptor? get filter => descriptor.objectValue('Fltr');

  /// Whether Photoshop evaluates this stack entry.
  bool get enabled => descriptor.booleanValue('enab') ?? true;

  /// Whether Photoshop should expose an options dialog for this entry.
  bool get hasOptions => descriptor.booleanValue('hasoptions') ?? filter != null;

  /// Normalized blending opacity applied to the filter result.
  double get opacity {
    final PsDescriptorNumber? value = descriptor.objectValue('blendOptions')?.numberValue('Opct');
    return switch (value) {
      PsDescriptorNumber(unit: '#Prc', value: final double percentage) => (percentage / 100).clamp(0, 1),
      _ => 1,
    };
  }

  /// Photoshop blend-mode identifier applied to the filter result.
  String get blendMode => descriptor.objectValue('blendOptions')?.enumerationIdentifier('Md  ') ?? 'Nrml';
}

/// The shared settings and ordered filters attached to one smart object.
///
/// The wrapper preserves the original [descriptor], including unknown fields,
/// while exposing the stable fields used by Photoshop's `filterFXStyle` data.
final class PsdSmartFilterStack {
  /// Complete `filterFXStyle` descriptor.
  final PsDescriptor descriptor;

  /// Creates a Photoshop-compatible smart-filter stack.
  factory PsdSmartFilterStack({
    required List<PsdSmartFilter> filters,
    bool enabled = true,
    bool validAtPosition = true,
    bool maskEnabled = true,
    bool maskLinked = true,
    bool maskExtendWithWhite = true,
  }) => PsdSmartFilterStack.fromDescriptor(
    PsDescriptor(
      name: '',
      classId: 'filterFXStyle',
      items: [
        PsDescriptorItem(
          key: 'enab',
          value: PsBooleanValue(value: enabled),
        ),
        PsDescriptorItem(
          key: 'validAtPosition',
          value: PsBooleanValue(value: validAtPosition),
        ),
        PsDescriptorItem(
          key: 'filterMaskEnable',
          value: PsBooleanValue(value: maskEnabled),
        ),
        PsDescriptorItem(
          key: 'filterMaskLinked',
          value: PsBooleanValue(value: maskLinked),
        ),
        PsDescriptorItem(
          key: 'filterMaskExtendWithWhite',
          value: PsBooleanValue(value: maskExtendWithWhite),
        ),
        PsDescriptorItem(
          key: 'filterFXList',
          value: PsListValue(
            values: [
              for (final PsdSmartFilter filter in filters) PsObjectValue(value: filter.descriptor),
            ],
          ),
        ),
      ],
    ),
  );

  /// Wraps an existing Photoshop smart-filter stack losslessly.
  const PsdSmartFilterStack.fromDescriptor(this.descriptor);

  /// Whether Photoshop evaluates the whole stack.
  bool get enabled => _boolean('enab', fallback: true);

  /// Whether the cached result is valid at the stored placement.
  bool get validAtPosition => _boolean('validAtPosition', fallback: true);

  /// Whether the shared smart-filter mask contributes to rendering.
  bool get maskEnabled => _boolean('filterMaskEnable', fallback: true);

  /// Whether the mask follows the smart object's transform.
  bool get maskLinked => _boolean('filterMaskLinked', fallback: true);

  /// Whether pixels beyond the stored mask bounds behave as white.
  bool get maskExtendWithWhite => _boolean('filterMaskExtendWithWhite', fallback: true);

  /// Ordered smart filters recognized inside the stack list.
  List<PsdSmartFilter> get filters {
    final PsDescriptorValue? list = descriptor.value('filterFXList');
    if (list is! PsListValue) {
      return const [];
    }
    return [
      for (final PsDescriptorValue value in list.values)
        if (value is PsObjectValue) PsdSmartFilter.fromDescriptor(value.value),
    ];
  }

  /// Reads one Boolean property while tolerating older incomplete descriptors.
  bool _boolean(String key, {required bool fallback}) => descriptor.booleanValue(key) ?? fallback;
}

/// Neutral RGB color used by filters without explicit color parameters.
const PsDescriptor _blackRgbDescriptor = PsDescriptor(
  name: '',
  classId: 'RGBC',
  items: [
    PsDescriptorItem(key: 'Rd  ', value: PsDoubleValue(value: 0)),
    PsDescriptorItem(key: 'Grn ', value: PsDoubleValue(value: 0)),
    PsDescriptorItem(key: 'Bl  ', value: PsDoubleValue(value: 0)),
  ],
);
