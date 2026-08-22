import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

void main() {
  group('smart objects', () {
    test('round-trips and edits modern placed-layer descriptors', () {
      final PsdPlacedTransform transform = _transform();
      final PsdDescriptorSmartObject source = PsdDescriptorSmartObject(
        descriptor: PsdDescriptor(
          name: '',
          classId: 'null',
          items: <PsdDescriptorItem>[
            PsdDescriptorItem(key: 'Idnt', value: PsdStringValue('resource-id\u0000')),
            PsdDescriptorItem(
              key: 'Trnf',
              value: PsdListValue(<PsdDescriptorValue>[
                for (final double coordinate in transform.toList()) PsdDoubleValue(coordinate),
              ]),
            ),
          ],
        ),
        trailingData: Uint8List.fromList(<int>[0, 0, 0]),
      );
      final Uint8List bytes = PsdSmartObjectCodec.encode(source);
      final PsdDescriptorSmartObject decoded = PsdSmartObjectCodec.decode(bytes, key: 'SoLd') as PsdDescriptorSmartObject;

      expect(decoded.linkedResourceId, 'resource-id');
      expect(decoded.transform?.bottomRightX, 120);
      expect(PsdSmartObjectCodec.encode(decoded), orderedEquals(bytes));

      final PsdDescriptorSmartObject edited = decoded
          .withLinkedResourceId('replacement')
          .withTransform(
            const PsdPlacedTransform(
              topLeftX: 1,
              topLeftY: 2,
              topRightX: 3,
              topRightY: 4,
              bottomRightX: 5,
              bottomRightY: 6,
              bottomLeftX: 7,
              bottomLeftY: 8,
            ),
          );
      expect(edited.linkedResourceId, 'replacement');
      expect(edited.transform?.bottomLeftY, 8);
    });

    test('round-trips legacy placed-layer metadata', () {
      final PsdLegacyPlacedLayer source = PsdLegacyPlacedLayer(
        id: 'legacy-id',
        transform: _transform(),
        warp: const PsdVersionedDescriptor(
          descriptor: PsdDescriptor(name: '', classId: 'warp'),
        ),
      );
      final Uint8List bytes = PsdSmartObjectCodec.encode(source);
      final PsdLegacyPlacedLayer decoded = PsdSmartObjectCodec.decode(bytes, key: 'plLd') as PsdLegacyPlacedLayer;

      expect(decoded.linkedResourceId, 'legacy-id');
      expect(decoded.placedType, 0);
      expect(decoded.transform.topRightX, 120);
      expect(PsdSmartObjectCodec.encode(decoded), orderedEquals(bytes));
    });

    test('round-trips object-array descriptor values', () {
      final PsdDescriptor source = PsdDescriptor(
        name: '',
        classId: 'null',
        items: <PsdDescriptorItem>[
          PsdDescriptorItem(
            key: 'quiltWarp',
            value: PsdObjectArrayValue(
              itemsCount: 2,
              value: PsdDescriptor(
                name: '',
                classId: 'rationalPoint',
                items: <PsdDescriptorItem>[
                  PsdDescriptorItem(
                    key: 'Hrzn',
                    value: PsdUnitFloatsValue(unit: '#Pxl', values: <double>[1, 2]),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

      final Uint8List bytes = PsdDescriptorCodec.encode(source);
      final PsdDescriptor decoded = PsdDescriptorCodec.decode(bytes);
      final PsdObjectArrayValue array = decoded.value('quiltWarp')! as PsdObjectArrayValue;

      expect(array.itemsCount, 2);
      expect(array.value.classId, 'rationalPoint');
      expect((array.value.value('Hrzn')! as PsdUnitFloatsValue).values, orderedEquals(<double>[1, 2]));
      expect(PsdDescriptorCodec.encode(decoded), orderedEquals(bytes));
    });

    test('round-trips embedded and external linked resources', () {
      final PsdLinkedResource embedded = PsdLinkedResource(
        type: PsdLinkedResourceType.embedded,
        id: 'resource-id',
        name: 'image.png',
        fileType: 'png ',
        data: Uint8List.fromList(<int>[0x89, 0x50, 0x4e, 0x47]),
        childDocumentId: '',
        assetModificationTime: 42.5,
        assetLocked: false,
      );
      final PsdLinkedResource external = PsdLinkedResource(
        type: PsdLinkedResourceType.external,
        version: 4,
        id: 'external-id',
        name: 'linked.psd',
        fileType: '8BPS',
        linkedFileDescriptor: PsdVersionedDescriptor(
          descriptor: PsdDescriptor(
            name: '',
            classId: 'null',
            items: <PsdDescriptorItem>[PsdDescriptorItem(key: 'full', value: PsdStringValue('/images/linked.psd'))],
          ),
        ),
        timestamp: const PsdLinkedResourceTimestamp(year: 2026, month: 8, day: 22, hour: 12, minute: 30, seconds: 15.5),
        externalFileSize: 123456,
      );
      final PsdLinkedResourceBlock block = PsdLinkedResourceBlock(
        entries: <PsdLinkedResourceEntry>[embedded, external],
        trailingData: Uint8List.fromList(<int>[0]),
      );
      final Uint8List bytes = PsdLinkedResourceCodec.encode(block);
      final PsdLinkedResourceBlock decoded = PsdLinkedResourceCodec.decode(bytes);

      expect(decoded.resources, hasLength(2));
      expect(decoded.resources.first.data, orderedEquals(<int>[0x89, 0x50, 0x4e, 0x47]));
      expect(decoded.resources.last.timestamp?.utcDateTime?.year, 2026);
      expect(PsdLinkedResourceCodec.encode(decoded), orderedEquals(bytes));
    });

    test('links smart-object layers to embedded files through the document', () {
      final PsdDescriptorSmartObject smartObject = PsdDescriptorSmartObject(
        descriptor: PsdDescriptor(
          name: '',
          classId: 'null',
          items: <PsdDescriptorItem>[PsdDescriptorItem(key: 'Idnt', value: PsdStringValue('asset-id\u0000'))],
        ),
      );
      final PsdLayer layer = PsdLayer(
        rectangle: const PsdRectangle.fromSize(width: 1, height: 1),
        name: 'Smart object',
      ).withSmartObject(smartObject);
      final PsdLinkedResource resource = PsdLinkedResource(
        type: PsdLinkedResourceType.embedded,
        id: 'asset-id',
        name: 'asset.psd',
        fileType: '8BPS',
        data: Uint8List.fromList(<int>[1, 2, 3]),
        childDocumentId: '',
        assetModificationTime: 0,
        assetLocked: false,
      );
      final PsdDocument document = PsdDocument(
        width: 1,
        height: 1,
        channels: 1,
        depth: 8,
        colorMode: PsdColorMode.grayscale,
        mergedImage: <Uint8List>[
          Uint8List.fromList(<int>[0]),
        ],
        layers: <PsdLayer>[layer],
      ).withLinkedResources(<PsdLinkedResource>[resource]);

      expect(document.linkedResourceFor(layer)?.name, 'asset.psd');
      final PsdDocument decoded = PsdCodec.decode(PsdCodec.encode(document));
      expect(decoded.layers.single.smartObject?.linkedResourceId, 'asset-id');
      expect(decoded.linkedResourceFor(decoded.layers.single)?.data, orderedEquals(<int>[1, 2, 3]));
    });
  });
}

PsdPlacedTransform _transform() => const PsdPlacedTransform(
  topLeftX: 0,
  topLeftY: 0,
  topRightX: 120,
  topRightY: 0,
  bottomRightX: 120,
  bottomRightY: 80,
  bottomLeftX: 0,
  bottomLeftY: 80,
);
