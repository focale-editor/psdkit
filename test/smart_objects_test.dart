import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Exercises smart-object descriptors and linked resources.
void main() {
  group('smart objects', () {
    test('round-trips and edits modern placed-layer descriptors', () {
      final PsdPlacedTransform transform = _transform();
      final PsdDescriptorSmartObject source = PsdDescriptorSmartObject(
        descriptor: PsDescriptor(
          name: '',
          classId: 'null',
          items: [
            const PsDescriptorItem(
              key: 'Idnt',
              value: PsStringValue(value: 'resource-id\u0000'),
            ),
            PsDescriptorItem(
              key: 'Trnf',
              value: PsListValue(
                values: <PsDescriptorValue>[
                  for (final double coordinate in transform.toList()) PsDoubleValue(value: coordinate),
                ],
              ),
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

    test('round-trips semantic smart-filter stack metadata', () {
      final PsdSmartFilter filter = PsdSmartFilter(
        filterId: 1198747202,
        name: 'Gaussian Blur',
        blendMode: 'Mltp',
        opacity: 0.625,
        enabled: false,
        filter: const PsDescriptor(
          name: 'Gaussian Blur',
          classId: 'GsnB',
          items: <PsDescriptorItem>[
            PsDescriptorItem(
              key: 'Rds ',
              value: PsUnitFloatValue(unit: '#Pxl', value: 4.5),
            ),
          ],
        ),
      );
      final PsdDescriptorSmartObject source =
          PsdDescriptorSmartObject(
            descriptor: const PsDescriptor(name: '', classId: 'null'),
          ).withSmartFilters(
            PsdSmartFilterStack(
              filters: [filter],
              maskEnabled: false,
              maskLinked: false,
            ),
          );

      final Uint8List bytes = PsdSmartObjectCodec.encode(source);
      final PsdDescriptorSmartObject decoded = PsdSmartObjectCodec.decode(
        bytes,
        key: 'SoLd',
      ) as PsdDescriptorSmartObject;
      final PsdSmartFilterStack stack = decoded.smartFilters!;
      final PsdSmartFilter decodedFilter = stack.filters.single;

      expect(stack.maskEnabled, isFalse);
      expect(stack.maskLinked, isFalse);
      expect(decodedFilter.filterId, 1198747202);
      expect(decodedFilter.name, 'Gaussian Blur');
      expect(decodedFilter.blendMode, 'Mltp');
      expect(decodedFilter.opacity, closeTo(0.625, 1e-12));
      expect(decodedFilter.enabled, isFalse);
      expect(decodedFilter.filter?.classId, 'GsnB');
      expect(PsdSmartObjectCodec.encode(decoded), orderedEquals(bytes));
    });

    test('round-trips legacy placed-layer metadata', () {
      final PsdLegacyPlacedLayer source = PsdLegacyPlacedLayer(
        id: 'legacy-id',
        transform: _transform(),
        warp: const PsdVersionedDescriptor(
          descriptor: PsDescriptor(name: '', classId: 'warp'),
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
      const PsDescriptor source = PsDescriptor(
        name: '',
        classId: 'null',
        items: <PsDescriptorItem>[
          PsDescriptorItem(
            key: 'quiltWarp',
            value: PsObjectArrayValue(
              itemsCount: 2,
              value: PsDescriptor(
                name: '',
                classId: 'rationalPoint',
                items: <PsDescriptorItem>[
                  PsDescriptorItem(
                    key: 'Hrzn',
                    value: PsUnitFloatsValue(unit: '#Pxl', values: <double>[1, 2]),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

      final Uint8List bytes = PsDescriptorCodec.encode(source);
      final PsDescriptor decoded = PsDescriptorCodec.decode(bytes);
      final PsObjectArrayValue array = decoded.value('quiltWarp')! as PsObjectArrayValue;

      expect(array.itemsCount, 2);
      expect(array.value.classId, 'rationalPoint');
      expect((array.value.value('Hrzn')! as PsUnitFloatsValue).values, orderedEquals(<double>[1, 2]));
      expect(PsDescriptorCodec.encode(decoded), orderedEquals(bytes));
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
        linkedFileDescriptor: const PsdVersionedDescriptor(
          descriptor: PsDescriptor(
            name: '',
            classId: 'null',
            items: <PsDescriptorItem>[
              PsDescriptorItem(
                key: 'full',
                value: PsStringValue(value: '/images/linked.psd'),
              ),
            ],
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
        descriptor: const PsDescriptor(
          name: '',
          classId: 'null',
          items: <PsDescriptorItem>[
            PsDescriptorItem(
              key: 'Idnt',
              value: PsStringValue(value: 'asset-id\u0000'),
            ),
          ],
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

/// Builds the representative rectangular placed-layer transform.
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
