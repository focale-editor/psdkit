import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Exercises layer blending options, locks, labels, and artboards.
void main() {
  group('PsdLayerBlendingOptions', () {
    test('decodes the padded blocks Photoshop writes', () {
      final PsdLayer layer = _layer(
        blocks: <PsdTaggedBlock>[
          _block('iOpa', <int>[128, 0, 0, 0]),
          _block('clbl', <int>[0, 0, 0, 0]),
          _block('infx', <int>[1, 0, 0, 0]),
          _block('knko', <int>[2, 0, 0, 0]),
          _block('tsly', <int>[0, 0, 0, 0]),
          _block('vmgm', <int>[1, 0, 0, 0]),
          _block('brst', <int>[0, 0, 0, 0, 0, 0, 0, 2]),
        ],
      );

      final PsdLayerBlendingOptions options = layer.blendingOptions;

      expect(options.fillOpacity, 128);
      expect(options.blendClippedLayers, isFalse);
      expect(options.blendInteriorEffects, isTrue);
      expect(options.knockout, PsdKnockout.deep);
      expect(options.transparencyShapesLayer, isFalse);
      expect(options.layerMaskHidesEffects, isNull);
      expect(options.vectorMaskHidesEffects, isTrue);
      expect(options.restrictedChannels, <int>[0, 2]);
      expect(options.isMalformed, isFalse);
    });

    test('defaults absent blocks and reports malformed ones', () {
      final PsdLayer layer = _layer(
        blocks: <PsdTaggedBlock>[
          _block('knko', <int>[3, 0, 0, 0]),
          _block('clbl', <int>[1, 5, 0, 0]),
          _block('brst', <int>[0, 0, 1]),
        ],
      );

      final PsdLayerBlendingOptions options = layer.blendingOptions;

      expect(options.fillOpacity, 255);
      expect(options.knockout, PsdKnockout.none);
      expect(options.blendClippedLayers, isTrue);
      expect(options.restrictedChannels, isEmpty);
      expect(options.malformedKeys, <String>{'knko', 'clbl', 'brst'});
    });

    test('writes Photoshop-style blocks that survive a document round trip', () {
      final PsdLayer layer = _layer(
        blocks: <PsdTaggedBlock>[
          _block('iOpa', <int>[1, 0, 0, 0]),
          _block('cust', <int>[9, 9]),
        ],
      ).withBlendingOptions(PsdLayerBlendingOptions(fillOpacity: 51, knockout: PsdKnockout.shallow, layerMaskHidesEffects: false, restrictedChannels: <int>[1]));

      final PsdLayer decoded = _roundTrip(layer);

      expect(decoded.additionalInfo.map((block) => block.key).where((key) => key != 'luni'), <String>['cust', 'iOpa', 'clbl', 'infx', 'knko', 'lmgm', 'brst']);
      expect(decoded.taggedBlock('iOpa')?.data, <int>[51, 0, 0, 0]);
      expect(decoded.blendingOptions.fillOpacity, 51);
      expect(decoded.blendingOptions.knockout, PsdKnockout.shallow);
      expect(decoded.blendingOptions.layerMaskHidesEffects, isFalse);
      expect(decoded.blendingOptions.restrictedChannels, <int>[1]);
    });

    test('rejects a fill opacity outside the byte range', () {
      expect(() => PsdLayerBlendingOptions(fillOpacity: 256).toBlocks(), throwsA(isA<PsWriteException>()));
    });
  });

  group('PsdLayerProtection', () {
    test('merges the lspf block with the record transparency flag', () {
      final PsdLayer background = _layer(
        flags: 0x09,
        blocks: <PsdTaggedBlock>[
          _block('lspf', <int>[0, 0, 0, 13]),
        ],
      );
      final PsdLayer flagOnly = _layer(flags: 0x01);

      expect(background.protection.transparency, isTrue);
      expect(background.protection.pixels, isFalse);
      expect(background.protection.position, isTrue);
      expect(background.protection.artboardNesting, isTrue);
      expect(flagOnly.protection.transparency, isTrue);
      expect(_layer().protection.flags, 0);
    });

    test('treats the all bit as every lock', () {
      final PsdLayerProtection protection = PsdLayerProtection.create(all: true);

      expect(protection.pixels && protection.position && protection.transparency, isTrue);
    });

    test('keeps the record flag in sync when writing', () {
      final PsdLayer locked = _layer(flags: 0x08).withProtection(PsdLayerProtection.create(transparency: true, pixels: true));
      final PsdLayer unlocked = locked.withProtection(const PsdLayerProtection());

      expect(locked.flags, 0x09);
      expect(locked.taggedBlock('lspf')?.data, <int>[0, 0, 0, 3]);
      expect(unlocked.flags, 0x08);
      expect(unlocked.protection.transparency, isFalse);
    });
  });

  group('PsdSheetColor', () {
    test('maps Photoshop indices, where zero means no label', () {
      expect(_layer(blocks: <PsdTaggedBlock>[_block('lclr', List<int>.filled(8, 0))]).sheetColor, PsdSheetColor.none);
      expect(
        _layer(
          blocks: <PsdTaggedBlock>[
            _block('lclr', <int>[0, 1, 0, 0, 0, 0, 0, 0]),
          ],
        ).sheetColor,
        PsdSheetColor.red,
      );
      expect(
        _layer(
          blocks: <PsdTaggedBlock>[
            _block('lclr', <int>[0, 99, 0, 0, 0, 0, 0, 0]),
          ],
        ).sheetColor,
        isNull,
      );
      expect(_layer().sheetColor, PsdSheetColor.none);
    });

    test('writes an eight-byte label block', () {
      final PsdLayer layer = _layer().withSheetColor(PsdSheetColor.violet);

      expect(layer.taggedBlock('lclr')?.data, <int>[0, 6, 0, 0, 0, 0, 0, 0]);
      expect(layer.sheetColor, PsdSheetColor.violet);
    });
  });

  group('PsdArtboard', () {
    test('creates, round-trips, and removes an artboard marker', () {
      final PsdArtboard artboard = PsdArtboard.create(
        left: 10,
        top: 20,
        right: 310,
        bottom: 620,
        background: PsdArtboardBackground.custom,
        color: PsColor.rgb(red: 12, green: 34, blue: 56),
        presetName: 'iPhone',
      );

      final PsdLayer decoded = _roundTrip(_layer().withArtboard(artboard));
      final PsdArtboard? read = decoded.artboard;

      expect(decoded.taggedBlock('artb')!.data.length % 4, 0);
      expect(<double?>[read?.left, read?.top, read?.right, read?.bottom], <double>[10, 20, 310, 620]);
      expect(read?.background, PsdArtboardBackground.custom);
      expect(read?.color?.blue, 56);
      expect(read?.presetName, 'iPhone');
      expect(decoded.withArtboard(null).taggedBlock('artb'), isNull);
    });

    test('ignores malformed artboard markers', () {
      expect(
        _layer(
          blocks: <PsdTaggedBlock>[
            _block('artb', <int>[0, 0, 0, 16, 1]),
          ],
        ).artboard,
        isNull,
      );
      expect(() => PsdArtboard.create(left: 5, top: 0, right: 5, bottom: 10), throwsA(isA<PsWriteException>()));
    });

    test('stores document-wide defaults in the artd block', () {
      final PsdDocument document = _document().withArtboardDefaults(PsdArtboardDefaults.create(count: 2, defaultBackground: PsdArtboardBackground.transparent));

      final PsdArtboardDefaults? defaults = PsdCodec.decode(PsdCodec.encode(document)).artboardDefaults;

      expect(defaults?.count, 2);
      expect(defaults?.autoNestEnabled, isTrue);
      expect(defaults?.defaultBackground, PsdArtboardBackground.transparent);
      expect(defaults?.defaultColor?.red, 255);
      expect(document.withArtboardDefaults(null).artboardDefaults, isNull);
    });
  });
}

/// Creates a one-pixel layer carrying [blocks].
PsdLayer _layer({int flags = 0, List<PsdTaggedBlock> blocks = const <PsdTaggedBlock>[]}) => PsdLayer(
  rectangle: const PsdRectangle.fromSize(width: 1, height: 1),
  name: 'Layer',
  flags: flags,
  channels: <PsdChannel>[for (int id = -1; id < 3; id++) PsdChannel(id: id, data: Uint8List(1))],
  additionalInfo: blocks,
);

/// Creates a tagged block from literal [bytes].
PsdTaggedBlock _block(String key, List<int> bytes) => PsdTaggedBlock(key: key, data: Uint8List.fromList(bytes));

/// Creates a one-pixel RGB document holding [layers].
PsdDocument _document({List<PsdLayer> layers = const <PsdLayer>[]}) => PsdDocument(
  width: 1,
  height: 1,
  channels: 3,
  depth: 8,
  colorMode: PsdColorMode.rgb,
  layers: layers,
  mergedImage: <Uint8List>[for (int channel = 0; channel < 3; channel++) Uint8List(1)],
);

/// Encodes and decodes [layer] inside a document.
PsdLayer _roundTrip(PsdLayer layer) => PsdCodec.decode(PsdCodec.encode(_document(layers: <PsdLayer>[layer]))).layers.single;
