import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Exercises Photoshop type-tool and text-engine data handling.
void main() {
  group('PsDescriptorCodec', () {
    test('round-trips text descriptor value types', () {
      final PsDescriptor source = PsDescriptor(
        name: 'Texte',
        classId: 'TxLr',
        items: <PsDescriptorItem>[
          const PsDescriptorItem(key: 'bool', value: PsBooleanValue(value: true)),
          const PsDescriptorItem(key: 'long', value: PsIntegerValue(value: -42)),
          const PsDescriptorItem(key: 'comp', value: PsLargeIntegerValue(value: 0x123456789)),
          const PsDescriptorItem(key: 'doub', value: PsDoubleValue(value: 1.25)),
          const PsDescriptorItem(
            key: 'unit',
            value: PsUnitFloatValue(unit: '#Pnt', value: 24),
          ),
          const PsDescriptorItem(
            key: 'text',
            value: PsStringValue(value: 'Été 😀\u0000'),
          ),
          const PsDescriptorItem(
            key: 'enum',
            value: PsEnumeratedValue(typeId: 'Ornt', value: 'Hrzn'),
          ),
          const PsDescriptorItem(
            key: 'obj ',
            value: PsObjectValue(
              value: PsDescriptor(name: '', classId: 'obj ', items: <PsDescriptorItem>[]),
            ),
          ),
          const PsDescriptorItem(
            key: 'list',
            value: PsListValue(values: <PsDescriptorValue>[PsBooleanValue(value: false), PsDoubleValue(value: 2.5)]),
          ),
          PsDescriptorItem(
            key: 'raw ',
            value: PsRawValue(value: Uint8List.fromList(<int>[0, 1, 255])),
          ),
          PsDescriptorItem(
            key: 'alis',
            value: PsAliasValue(value: Uint8List.fromList(<int>[4, 5])),
          ),
          const PsDescriptorItem(
            key: 'type',
            value: PsClassValue(name: 'Classe', classId: 'TxLr'),
          ),
        ],
      );

      final Uint8List encoded = PsDescriptorCodec.encode(source);
      final PsDescriptor decoded = PsDescriptorCodec.decode(encoded);

      expect(PsDescriptorCodec.encode(decoded), orderedEquals(encoded));
      expect((decoded.value('text')! as PsStringValue).value, 'Été 😀\u0000');
      expect((decoded.value('unit')! as PsUnitFloatValue).value, 24);
      expect((decoded.value('list')! as PsListValue).values, hasLength(2));
    });
  });

  group('PsdTypeTool', () {
    test('creates styled text without a source PSD', () {
      final PsdTypeTool source = PsdTypeTool.fromText(
        content: const PsdTextContent(
          text: 'Bonjour',
          orientation: PsdTextOrientation.vertical,
          styleRuns: <PsdTextStyleRun>[
            PsdTextStyleRun(
              start: 0,
              length: 3,
              style: PsdTextStyle(
                fontFamily: 'Inter-Bold',
                fontSize: 20,
                color: PsdTextColor(alpha: 255, red: 10, green: 20, blue: 30),
                fauxBold: true,
              ),
            ),
            PsdTextStyleRun(start: 3, length: 4, style: PsdTextStyle(fontFamily: 'Inter-Regular', fontSize: 18)),
          ],
          paragraphs: <PsdTextParagraph>[
            PsdTextParagraph(start: 0, length: 7, justification: PsdTextJustification.center),
          ],
        ),
        bounds: const PsdTextBounds(left: 10, top: 20, right: 210, bottom: 120),
      );

      final PsdTypeTool decoded = PsdTypeToolCodec.decode(PsdTypeToolCodec.encode(source));

      expect(decoded.text, 'Bonjour');
      expect(decoded.orientation, PsdTextOrientation.vertical);
      expect(decoded.content.styleRuns.map((run) => run.length), orderedEquals(<int>[3, 4]));
      expect(decoded.content.styleRuns.last.style.fontFamily, 'Inter-Regular');
      expect(decoded.content.paragraphs.single.justification, PsdTextJustification.center);
      expect(decoded.bounds.right, 210);
    });

    test('extracts text, font, size, color, and paragraph alignment', () {
      final PsdTypeTool typeTool = _typeTool('Salut');

      final PsdTextContent content = typeTool.content;

      expect(typeTool.text, 'Salut');
      expect(content.text, 'Salut');
      expect(content.orientation, PsdTextOrientation.horizontal);
      expect(content.styleRuns, hasLength(1));
      expect(content.styleRuns.single.start, 0);
      expect(content.styleRuns.single.length, 5);
      expect(content.styleRuns.single.style.fontFamily, 'Inter-Regular');
      expect(content.styleRuns.single.style.fontSize, 24);
      expect(content.styleRuns.single.style.color?.argb, 0xff1a334d);
      expect(content.styleRuns.single.style.fauxBold, isTrue);
      expect(content.paragraphs.single.justification, PsdTextJustification.right);
    });

    test('updates descriptor and UTF-16 EngineData without losing metadata', () {
      const String replacement =
          r'A (B) \ 😀'
          '\nC';
      final PsdTypeTool source = _typeTool('Salut');

      final Uint8List encoded = PsdTypeToolCodec.encode(source.withText(replacement));
      final PsdTypeTool decoded = PsdTypeToolCodec.decode(encoded);

      expect(
        decoded.text,
        r'A (B) \ 😀'
        '\rC',
      );
      expect(
        decoded.content.text,
        r'A (B) \ 😀'
        '\rC',
      );
      expect(decoded.content.styleRuns.single.style.fontFamily, 'Inter-Regular');
      expect(decoded.warpDescriptor.classId, 'warp');
      expect(decoded.trailingData, orderedEquals(<int>[0, 0]));
    });

    test('survives a complete layered PSD export and import', () {
      final PsdLayer textLayer = PsdLayer(
        rectangle: const PsdRectangle(top: 0, left: 0, bottom: 1, right: 1),
        name: 'Texte',
        channels: <PsdChannel>[
          for (final int id in <int>[0, 1, 2, -1]) PsdChannel(id: id, data: Uint8List.fromList(<int>[if (id == -1) 255 else 0])),
        ],
      ).withTypeTool(_typeTool('Bonjour'));
      final PsdDocument source = PsdDocument(
        width: 1,
        height: 1,
        channels: 3,
        depth: 8,
        colorMode: PsdColorMode.rgb,
        layers: <PsdLayer>[textLayer],
        mergedImage: <Uint8List>[
          for (int index = 0; index < 3; index++) Uint8List.fromList(<int>[0]),
        ],
      );

      final PsdDocument decoded = PsdCodec.decode(PsdCodec.encode(source));

      expect(decoded.layers.single.typeTool?.text, 'Bonjour');
      expect(decoded.layers.single.typeTool?.content.styleRuns.single.style.fontFamily, 'Inter-Regular');
    });
  });
}

/// Builds a representative type-tool payload containing [text].
PsdTypeTool _typeTool(String text) => PsdTypeTool(
  textDescriptor: PsDescriptor(
    name: '',
    classId: 'TxLr',
    items: <PsDescriptorItem>[
      PsDescriptorItem(
        key: 'Txt ',
        value: PsStringValue(value: '$text\u0000'),
      ),
      const PsDescriptorItem(
        key: 'Ornt',
        value: PsEnumeratedValue(typeId: 'Ornt', value: 'Hrzn'),
      ),
      PsDescriptorItem(
        key: 'EngineData',
        value: PsRawValue(value: _engineData(text)),
      ),
    ],
  ),
  warpDescriptor: const PsDescriptor(name: '', classId: 'warp'),
  bounds: const PsdTextBounds(left: 0, top: 0, right: 100, bottom: 40),
  trailingData: Uint8List.fromList(<int>[0, 0]),
);

/// Builds minimal Photoshop text-engine data containing [text].
Uint8List _engineData(String text) {
  final BytesBuilder bytes = BytesBuilder(copy: false)
    ..add(
      '''<< /EngineDict <<
/Editor << /Text ('''
          .codeUnits,
    )
    ..add(_utf16(text))
    ..add(
      ''') >>
/StyleRun << /RunArray [ << /StyleSheet << /StyleSheetData <<
/Font 0 /FontSize 24 /FauxBold true /FauxItalic false
/Underline 0 /Strikethrough 0 /Tracking -10 /AutoLeading true
/FillColor << /Type 1 /Values [ 1 0.1 0.2 0.3 ] >>
>> >> >> ] /RunLengthArray [ ${text.length + 1} ] >>
/ParagraphRun << /RunArray [ << /ParagraphSheet << /Properties <<
/Justification 2 >> >> >> ] /RunLengthArray [ ${text.length + 1} ] >>
>> /ResourceDict << /FontSet [ << /Name ('''
          .codeUnits,
    )
    ..add(_utf16('Inter-Regular'))
    ..add(') >> ] >> >>'.codeUnits);
  return bytes.takeBytes();
}

/// Encodes [value] as terminated big-endian UTF-16 with a byte-order mark.
Uint8List _utf16(String value) {
  final BytesBuilder bytes = BytesBuilder(copy: false)..add(const <int>[0xfe, 0xff]);
  for (final int unit in '$value\u0000'.codeUnits) {
    bytes.add(<int>[unit >> 8, unit & 0xff]);
  }
  return bytes.takeBytes();
}
