import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Exercises Photoshop's per-layer composition metadata.
void main() {
  group('PsdLayerComps', () {
    test('round-trips historical appearance and Blend If values', () {
      const PsdLayerCompBlendRange gray = PsdLayerCompBlendRange(
        channel: 'Gry ',
        sourceBlack: 12,
        sourceBlackSplit: 24,
        sourceWhiteSplit: 220,
        sourceWhite: 240,
        destinationBlack: 3,
        destinationBlackSplit: 8,
        destinationWhiteSplit: 230,
        destinationWhite: 250,
      );
      final PsdLayerEffects effects = PsdLayerEffects.create(
        effects: [
          PsdLayerEffect.create(
            type: PsdLayerEffectType.dropShadow,
            opacity: 62,
          ),
        ],
      );
      final PsdLayerCompLayerData metadata = PsdLayerCompLayerData.create(
        layerIdentifier: 7,
        originalEffectsReferencePoint: (
          horizontal: 10,
          vertical: 20,
        ),
        states: [
          PsdLayerCompLayerState.create(
            compIdentifiers: [42, 43],
            visible: false,
            positionOffset: (horizontal: -4, vertical: 6),
            blendOptions: PsdLayerCompBlendOptions.create(
              opacityPercent: 37.5,
              blendMode: 'Mltp',
              fillOpacityPercent: 80,
              blendingRanges: const [gray],
            ),
            layerEffects: effects,
          ),
          PsdLayerCompLayerState.create(compIdentifiers: [0]),
        ],
      );
      final PsdLayer source = _layer().withLayerCompData(metadata);

      final PsdLayer decoded = PsdCodec.decode(
        PsdCodec.encode(_document(layer: source)),
      ).layers.single;
      final PsdLayerCompLayerData restored = decoded.layerCompData!;
      final PsdLayerCompLayerState state = restored.statesByCompIdentifier[42]!;
      final PsdLayerCompBlendOptions options = state.blendOptions!;

      expect(restored.layerIdentifier, 7);
      expect(restored.originalEffectsReferencePoint?.horizontal, 10);
      expect(state.compIdentifiers, [42, 43]);
      expect(state.visible, isFalse);
      expect(state.positionOffset?.horizontal, -4);
      expect(state.positionOffset?.vertical, 6);
      expect(options.opacityPercent, 37.5);
      expect(options.blendMode, 'Mltp');
      expect(options.fillOpacityPercent, 80);
      expect(options.blendingRanges, hasLength(1));
      expect(options.blendingRanges!.single.channel, 'Gry ');
      expect(options.blendingRanges!.single.sourceBlackSplit, 24);
      expect(state.layerEffects?.effects.single.opacity, 62);
      expect(
        restored.statesByCompIdentifier[43]!.compIdentifiers,
        state.compIdentifiers,
      );
    });

    test('retains unknown state properties and removes cmls cleanly', () {
      const PsDescriptor stateDescriptor = PsDescriptor(
        name: '\u0000',
        classId: 'null',
        items: [
          PsDescriptorItem(
            key: 'futureAdobeKey',
            value: PsStringValue(value: 'retained'),
          ),
          PsDescriptorItem(
            key: 'compList',
            value: PsListValue(values: [PsIntegerValue(value: 5)]),
          ),
        ],
      );
      final PsdLayer withMetadata = _layer().withLayerCompData(
        PsdLayerCompLayerData.create(
          layerIdentifier: 1,
          originalEffectsReferencePoint: (
            horizontal: 0,
            vertical: 0,
          ),
          states: const [
            PsdLayerCompLayerState(descriptor: stateDescriptor),
          ],
        ),
      );

      final PsdLayer decoded = PsdCodec.decode(
        PsdCodec.encode(_document(layer: withMetadata)),
      ).layers.single;
      final PsDescriptorValue? retained = decoded.layerCompData?.states.single.descriptor.value('futureAdobeKey');
      final PsdLayer removed = decoded.withLayerCompData(null);

      expect((retained! as PsStringValue).value, 'retained');
      expect(removed.taggedBlock('shmd'), isNull);
      expect(removed.layerCompData, isNull);
    });

    test('rejects malformed and duplicate Blend If ranges', () {
      const PsdLayerCompBlendRange malformed = PsdLayerCompBlendRange(
        channel: 'Gry ',
        sourceBlack: 20,
        sourceBlackSplit: 10,
        sourceWhiteSplit: 255,
        sourceWhite: 255,
        destinationBlack: 0,
        destinationBlackSplit: 0,
        destinationWhiteSplit: 255,
        destinationWhite: 255,
      );
      final PsDescriptor duplicateRanges = PsDescriptor(
        name: '',
        classId: 'null',
        items: [
          PsDescriptorItem(
            key: 'Blnd',
            value: PsListValue(
              values: [
                PsObjectValue(value: _validGrayRange),
                PsObjectValue(value: _validGrayRange),
              ],
            ),
          ),
        ],
      );

      expect(
        () => PsdLayerCompBlendOptions.create(
          blendingRanges: [malformed],
        ),
        throwsA(isA<PsWriteException>()),
      );
      expect(
        PsdLayerCompBlendOptions(
          descriptor: duplicateRanges,
        ).blendingRanges,
        isNull,
      );
    });
  });
}

/// A valid neutral grayscale Blend If descriptor used by malformed-list tests.
final PsDescriptor _validGrayRange = PsDescriptor(
  name: '',
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
            value: 'Gry ',
          ),
        ],
      ),
    ),
    const PsDescriptorItem(key: 'SrcB', value: PsIntegerValue(value: 0)),
    const PsDescriptorItem(key: 'Srcl', value: PsIntegerValue(value: 0)),
    const PsDescriptorItem(key: 'SrcW', value: PsIntegerValue(value: 255)),
    const PsDescriptorItem(key: 'Srcm', value: PsIntegerValue(value: 255)),
    const PsDescriptorItem(key: 'DstB', value: PsIntegerValue(value: 0)),
    const PsDescriptorItem(key: 'Dstl', value: PsIntegerValue(value: 0)),
    const PsDescriptorItem(key: 'DstW', value: PsIntegerValue(value: 255)),
    const PsDescriptorItem(key: 'Dstt', value: PsIntegerValue(value: 255)),
  ],
);

/// Creates a minimal writable RGB document containing [layer].
PsdDocument _document({required PsdLayer layer}) => PsdDocument(
  width: 1,
  height: 1,
  channels: 3,
  depth: 8,
  colorMode: PsdColorMode.rgb,
  layers: [layer],
  mergedImage: [
    Uint8List.fromList([0]),
    Uint8List.fromList([0]),
    Uint8List.fromList([0]),
  ],
);

/// Creates a minimal layer record without pixel channels.
PsdLayer _layer() => PsdLayer(
  rectangle: const PsdRectangle(top: 0, left: 0, bottom: 0, right: 0),
  name: 'Layer',
);
