import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

void main() {
  group('PsdVectorPath', () {
    test('round-trips closed and open cubic Bezier subpaths', () {
      final PsdVectorPath semantic = PsdVectorPath.fromSubpaths(
        startsWithAllPixels: true,
        subpaths: const <PsdSubpath>[
          PsdSubpath(
            closed: true,
            operation: 1,
            knots: <PsdBezierKnot>[
              PsdBezierKnot(
                incoming: PsdPathPoint(x: 0.125, y: 0.25),
                anchor: PsdPathPoint(x: 0.25, y: 0.25),
                outgoing: PsdPathPoint(x: 0.375, y: 0.25),
              ),
              PsdBezierKnot.corner(PsdPathPoint(x: 0.75, y: 0.75)),
            ],
          ),
          PsdSubpath(
            closed: false,
            operation: 2,
            knots: <PsdBezierKnot>[
              PsdBezierKnot(
                incoming: PsdPathPoint(x: -0.25, y: 0.5),
                anchor: PsdPathPoint(x: 0, y: 0.5),
                outgoing: PsdPathPoint(x: 1.25, y: 0.5),
                linked: false,
              ),
            ],
          ),
        ],
      );

      final Uint8List encoded = PsdVectorPathCodec.encode(semantic);
      final PsdVectorPath decoded = PsdVectorPathCodec.decode(encoded);

      expect(PsdVectorPathCodec.encode(decoded), orderedEquals(encoded));
      expect(decoded.startsWithAllPixels, isTrue);
      expect(decoded.subpaths, hasLength(2));
      expect(decoded.subpaths.first.operationType, PsdPathOperation.combine);
      expect(decoded.subpaths.last.operationType, PsdPathOperation.subtract);
      expect(decoded.subpaths.first.knots.last.linked, isFalse);
      expect(decoded.subpaths.last.knots.single.outgoing.x, 1.25);
      expect(decoded.subpaths.last.knots.single.anchor.y, 0.5);
      final PsdPathPoint pixels = PsdPathPoint.fromPixels(x: 50, y: 25, width: 200, height: 100);
      expect(pixels, isA<PsdPathPoint>());
      expect(pixels.x, 0.25);
      expect(pixels.pixelY(100), 25);
    });

    test('preserves clipboard and unknown path records', () {
      final PsdVectorPath source = PsdVectorPath(
        records: <PsdPathRecord>[
          PsdPathClipboardRecord(top: 0.1, left: 0.2, bottom: 0.8, right: 0.9, resolution: 72),
          PsdUnknownPathRecord(selector: 42, data: Uint8List.fromList(List<int>.generate(24, (index) => index))),
        ],
      );

      final Uint8List encoded = PsdVectorPathCodec.encode(source);
      final PsdVectorPath decoded = PsdVectorPathCodec.decode(encoded);

      expect(PsdVectorPathCodec.encode(decoded), orderedEquals(encoded));
      expect((decoded.records.first as PsdPathClipboardRecord).resolution, 72);
      expect((decoded.records.last as PsdUnknownPathRecord).selector, 42);
    });
  });

  group('PsdVectorMask', () {
    test('round-trips flags, records, and trailing data', () {
      final PsdVectorMask source = PsdVectorMask(
        flags: 7,
        blockKey: 'vsms',
        path: PsdVectorPath.fromSubpaths(
          subpaths: const <PsdSubpath>[
            PsdSubpath(
              closed: true,
              knots: <PsdBezierKnot>[
                PsdBezierKnot.corner(PsdPathPoint(x: 0.25, y: 0.5)),
              ],
            ),
          ],
        ),
        trailingData: Uint8List.fromList(<int>[9, 8]),
      );

      final Uint8List encoded = PsdVectorMaskCodec.encode(source);
      final PsdVectorMask decoded = PsdVectorMaskCodec.decode(encoded, key: 'vsms');

      expect(PsdVectorMaskCodec.encode(decoded), orderedEquals(encoded));
      expect(decoded.blockKey, 'vsms');
      expect(decoded.inverted, isTrue);
      expect(decoded.notLinked, isTrue);
      expect(decoded.disabled, isTrue);
      expect(decoded.path.subpaths.single.knots.single.anchor.x, 0.25);
      expect(decoded.trailingData, orderedEquals(<int>[9, 8]));
    });

    test('attaches a mask without replacing its raster mask metadata', () {
      final PsdLayerMask rasterMask = PsdLayerMask(
        rectangle: const PsdRectangle(top: 0, left: 0, bottom: 1, right: 1),
        defaultColor: 255,
        flags: 0,
        data: Uint8List(0),
      );
      final PsdLayer source = PsdLayer(
        rectangle: const PsdRectangle(top: 0, left: 0, bottom: 1, right: 1),
        name: 'Vector',
        mask: rasterMask,
        additionalInfo: <PsdTaggedBlock>[
          PsdTaggedBlock(key: 'vsms', data: Uint8List.fromList(<int>[1, 2, 3])),
        ],
      );
      final PsdVectorMask vectorMask = PsdVectorMask(path: PsdVectorPath.fromSubpaths(subpaths: const <PsdSubpath>[]));

      final PsdLayer edited = source.withVectorMask(vectorMask);

      expect(identical(edited.mask, rasterMask), isTrue);
      expect(edited.taggedBlock('vsms'), isNull);
      expect(edited.vectorMask?.path.subpaths, isEmpty);
    });
  });

  test('stores named paths as document image resources', () {
    final PsdDocument source =
        PsdDocument(
          width: 1,
          height: 1,
          channels: 3,
          depth: 8,
          colorMode: PsdColorMode.rgb,
          imageResources: <PsdImageResource>[
            PsdImageResource(id: 1060, name: 'Keep', data: Uint8List.fromList(<int>[1, 2, 3])),
          ],
          mergedImage: <Uint8List>[
            for (int index = 0; index < 3; index++) Uint8List.fromList(<int>[0]),
          ],
        ).withNamedPaths(<PsdNamedPath>[
          PsdNamedPath(
            resourceId: 2000,
            name: 'Logo',
            path: PsdVectorPath.fromSubpaths(
              subpaths: const <PsdSubpath>[
                PsdSubpath(
                  closed: true,
                  knots: <PsdBezierKnot>[
                    PsdBezierKnot.corner(PsdPathPoint(x: 0, y: 0)),
                    PsdBezierKnot.corner(PsdPathPoint(x: 1, y: 0)),
                    PsdBezierKnot.corner(PsdPathPoint(x: 1, y: 1)),
                  ],
                ),
              ],
            ),
          ),
        ]);

    final PsdDocument decoded = PsdCodec.decode(PsdCodec.encode(source));

    expect(decoded.imageResources.where((resource) => resource.id == 1060), hasLength(1));
    expect(decoded.namedPaths.single.name, 'Logo');
    expect(decoded.namedPaths.single.path.subpaths.single.knots, hasLength(3));
  });
}
