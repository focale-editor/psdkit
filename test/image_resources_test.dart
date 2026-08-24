import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Exercises typed Photoshop image-resource codecs.
void main() {
  group('image resources', () {
    test('round-trips resolution, colors, flags, and guides', () {
      final List<PsdImageResourceData> values = <PsdImageResourceData>[
        const PsdResolutionInfo(
          horizontalFixed: 300 * 65536,
          horizontalResolutionUnit: 1,
          widthUnit: 1,
          verticalFixed: 144 * 65536,
          verticalResolutionUnit: 1,
          heightUnit: 2,
        ),
        const PsdImageResourceColor(colorSpace: 0, components: <int>[65535, 32768, 1, 0]),
        const PsdPrintFlags(labels: true, cropMarks: true, interpolate: true, printFlags: false),
        const PsdGridAndGuides(
          guides: <PsdGuide>[
            PsdGuide(location: 320, direction: 0),
            PsdGuide(location: 640, direction: 1),
          ],
        ),
      ];

      final List<PsdImageResourceData> decoded = values.map(_roundTrip).toList();

      expect((decoded[0] as PsdResolutionInfo).horizontal, 300);
      expect((decoded[1] as PsdImageResourceColor).components[1], 32768);
      expect((decoded[2] as PsdPrintFlags).cropMarks, isTrue);
      expect((decoded[3] as PsdGridAndGuides).guides.last.directionType, PsdGuideDirection.horizontal);
    });

    test('round-trips halftone and transfer functions', () {
      const PsdHalftoneScreens halftone = PsdHalftoneScreens(
        resourceId: PsdImageResourceIds.colorHalftoning,
        screens: <PsdHalftoneScreen>[
          PsdHalftoneScreen(frequency: 60.5, unit: 1, angle: 15.25, shape: 2, useAccurate: true),
        ],
      );
      const PsdTransferFunctions transfer = PsdTransferFunctions(
        resourceId: PsdImageResourceIds.colorTransferFunctions,
        functions: <PsdTransferFunction>[
          PsdTransferFunction(curve: <int>[0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 1000], override: 1),
        ],
      );

      expect((_roundTrip(halftone) as PsdHalftoneScreens).screens.single.angle, 15.25);
      expect((_roundTrip(transfer) as PsdTransferFunctions).functions.single.curve.last, 1000);
    });

    test('round-trips thumbnails, ICC headers, and XMP text', () {
      final PsdThumbnailResource thumbnail = PsdThumbnailResource(
        format: 1,
        width: 2,
        height: 1,
        rowBytes: 8,
        totalSize: 8,
        bitsPerPixel: 24,
        planes: 1,
        data: Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0xd9]),
      );
      final Uint8List profile = Uint8List(128);
      final ByteData header = ByteData.sublistView(profile)
        ..setUint32(0, 128)
        ..setUint32(8, 0x04300000);
      profile.setRange(12, 16, 'mntr'.codeUnits);
      profile.setRange(16, 20, 'RGB '.codeUnits);
      profile.setRange(20, 24, 'XYZ '.codeUnits);
      profile.setRange(36, 40, 'acsp'.codeUnits);
      final PsdIccProfileResource icc = PsdIccProfileResource(data: profile);
      final PsdTextImageResource xmp = PsdTextImageResource(resourceId: PsdImageResourceIds.xmp, value: '<x:xmpmeta>été</x:xmpmeta>', utf8: true);

      expect((_roundTrip(thumbnail) as PsdThumbnailResource).jpeg, isTrue);
      expect((_roundTrip(icc) as PsdIccProfileResource).hasValidSignature, isTrue);
      expect((_roundTrip(xmp) as PsdTextImageResource).value, contains('été'));
      expect(header.getUint32(0), 128);
    });

    test('round-trips lists, display records, URLs, and version info', () {
      final List<PsdImageResourceData> values = <PsdImageResourceData>[
        const PsdStringListImageResource(resourceId: PsdImageResourceIds.alphaNamesUnicode, values: <String>['Alpha', 'Éclat'], unicode: true),
        const PsdIntegerListImageResource(
          resourceId: PsdImageResourceIds.layerSelectionIds,
          values: <int>[4, 8, 15, 16, 23, 42],
          valueBytes: 4,
          layout: PsdImageResourceListLayout.uint16Count,
        ),
        const PsdDisplayInfo(
          version: 1,
          channels: <PsdAlphaChannelDisplay>[
            PsdAlphaChannelDisplay(colorSpace: 0, components: <int>[65535, 0, 32768, 0], opacity: 75, mode: 2),
          ],
        ),
        const PsdUrlList(items: <PsdUrlItem>[PsdUrlItem(number: 1, id: 42, name: 'https://example.com')]),
        const PsdVersionInfo(version: 1, hasRealMergedData: true, writerName: 'PsdKit', readerName: 'Photoshop', fileVersion: 1),
      ];

      final List<PsdImageResourceData> decoded = values.map(_roundTrip).toList();

      expect((decoded[0] as PsdStringListImageResource).values.last, 'Éclat');
      expect((decoded[1] as PsdIntegerListImageResource).values, orderedEquals(<int>[4, 8, 15, 16, 23, 42]));
      expect((decoded[2] as PsdDisplayInfo).channels.single.opacity, 75);
      expect((decoded[3] as PsdUrlList).items.single.id, 42);
      expect((decoded[4] as PsdVersionInfo).writerName, 'PsdKit');
    });

    test('round-trips descriptor resources, slices, and paths', () {
      final PsDescriptor descriptor = PsDescriptor(
        name: '',
        classId: 'null',
        items: <PsDescriptorItem>[
          const PsDescriptorItem(
            key: 'Nm  ',
            value: PsStringValue(value: 'Item'),
          ),
          PsDescriptorItem(
            key: 'null',
            value: PsReferenceValue(
              values: <PsDescriptorValue>[
                const PsPropertyValue(name: '', classId: 'Dcmn', keyId: 'Ttl '),
                const PsReferenceClassValue(name: '', classId: 'Lyr '),
                PsEnumeratedReferenceValue(name: '', classId: 'Lyr ', typeId: 'Ordn', value: 'Trgt'),
                const PsOffsetValue(name: '', classId: 'Lyr ', value: 2),
                const PsIdentifierValue(value: 7),
                const PsIndexValue(value: 3),
                const PsNameValue(name: '', classId: 'Lyr ', value: 'Calque'),
              ],
            ),
          ),
          PsDescriptorItem(
            key: 'Pth ',
            value: PsPathValue(value: Uint8List.fromList(<int>[1, 2, 3])),
          ),
        ],
      );
      final PsdDescriptorImageResource layerComps = PsdDescriptorImageResource(
        resourceId: PsdImageResourceIds.layerComps,
        descriptorVersion: 16,
        descriptor: descriptor,
        trailingData: Uint8List.fromList(<int>[0]),
      );
      final PsdSlicesResource slices = PsdSlicesResource(
        version: 8,
        descriptorVersion: 16,
        descriptor: descriptor,
        trailingData: Uint8List(0),
      );
      final PsdVectorPath path = PsdVectorPath.fromSubpaths(
        subpaths: const <PsdSubpath>[
          PsdSubpath(
            closed: true,
            knots: <PsdBezierKnot>[
              PsdBezierKnot.corner(anchor: PsdPathPoint(x: 0, y: 0)),
              PsdBezierKnot.corner(anchor: PsdPathPoint(x: 1, y: 1)),
            ],
          ),
        ],
      );

      final PsDescriptor decodedDescriptor = (_roundTrip(layerComps) as PsdDescriptorImageResource).descriptor;
      expect(decodedDescriptor.value('Nm  '), isA<PsStringValue>());
      expect((decodedDescriptor.value('null') as PsReferenceValue).values, hasLength(7));
      expect(decodedDescriptor.value('Pth '), isA<PsPathValue>());
      expect((_roundTrip(slices) as PsdSlicesResource).version, 8);
      expect((_roundTrip(PsdPathImageResource(resourceId: 2000, path: path)) as PsdPathImageResource).path.subpaths.single.knots, hasLength(2));
    });

    test('edits and removes document resources without disturbing others', () {
      final PsdDocument source = PsdDocument(
        width: 1,
        height: 1,
        channels: 1,
        depth: 8,
        colorMode: PsdColorMode.grayscale,
        mergedImage: <Uint8List>[
          Uint8List.fromList(<int>[0]),
        ],
        imageResources: <PsdImageResource>[
          PsdImageResource(id: 1092, data: Uint8List.fromList(<int>[9, 8, 7])),
        ],
      );

      final PsdDocument edited = source.withImageResourceData(const PsdIntegerImageResource(resourceId: PsdImageResourceIds.globalAngle, value: 120));
      final PsdDocument decoded = PsdCodec.decode(PsdCodec.encode(edited));

      expect((decoded.decodedImageResource(PsdImageResourceIds.globalAngle)! as PsdIntegerImageResource).value, 120);
      expect(decoded.imageResource(1092)?.data, orderedEquals(<int>[9, 8, 7]));
      expect(decoded.withoutImageResource(1092).imageResource(1092), isNull);
      expect(decoded.imageResource(1092)?.decoded, isA<PsdRawImageResource>());
    });
  });
}

/// Encodes and decodes [value], asserting byte-stable serialization.
PsdImageResourceData _roundTrip(PsdImageResourceData value) {
  final Uint8List bytes = PsdImageResourceCodec.encode(value);
  final PsdImageResourceData decoded = PsdImageResourceCodec.decode(bytes, resourceId: value.resourceId);
  expect(PsdImageResourceCodec.encode(decoded), orderedEquals(bytes));
  return decoded;
}
