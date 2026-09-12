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
      expect(
        String.fromCharCodes(source.engineData!),
        contains('/Justification 2'),
      );
      expect(decoded.bounds.right, 210);
    });

    test('uses Adobe paragraph justification values', () {
      const Map<PsdTextJustification, int> values = {
        PsdTextJustification.left: 0,
        PsdTextJustification.right: 1,
        PsdTextJustification.center: 2,
        PsdTextJustification.justifyLeft: 3,
        PsdTextJustification.justifyRight: 4,
        PsdTextJustification.justifyCenter: 5,
        PsdTextJustification.justifyAll: 6,
      };

      for (final MapEntry<PsdTextJustification, int> entry in values.entries) {
        final PsdTypeTool source = PsdTypeTool.fromText(
          content: PsdTextContent(
            text: 'A',
            orientation: PsdTextOrientation.horizontal,
            paragraphs: [
              PsdTextParagraph(
                start: 0,
                length: 1,
                justification: entry.key,
              ),
            ],
          ),
        );

        expect(
          String.fromCharCodes(source.engineData!),
          contains('/Justification ${entry.value}'),
        );
        expect(
          PsdTypeToolCodec.decode(
            PsdTypeToolCodec.encode(source),
          ).content.paragraphs.single.justification,
          entry.key,
        );
      }
    });

    test('extracts text, font, size, color, and paragraph alignment', () {
      final PsdTypeTool typeTool = _typeTool('Salut');

      final PsdTextContent content = typeTool.content;

      expect(typeTool.text, 'Salut');
      expect(content.text, 'Salut');
      expect(content.orientation, PsdTextOrientation.horizontal);
      expect(content.hasShapeMetadata, isFalse);
      expect(content.styleRuns, hasLength(1));
      expect(content.styleRuns.single.start, 0);
      expect(content.styleRuns.single.length, 5);
      expect(content.styleRuns.single.style.fontFamily, 'Inter-Regular');
      expect(content.styleRuns.single.style.fontSize, 24);
      expect(content.styleRuns.single.style.color?.argb, 0xff1a334d);
      expect(content.styleRuns.single.style.fauxBold, isTrue);
      expect(content.paragraphs.single.justification, PsdTextJustification.center);
    });

    test('removes Photoshop final engine paragraph mark', () {
      final PsdTextContent content = _typeTool(
        'Salut',
        terminalParagraphMark: true,
      ).content;

      expect(content.text, 'Salut');
      expect(content.styleRuns.single.length, 5);
      expect(content.paragraphs.single.length, 5);
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

    test('uses the required final carriage return in generated and edited EngineData', () {
      final PsdTypeTool generated = PsdTypeTool.fromText(
        content: const PsdTextContent(
          text: 'Bonjour',
          orientation: PsdTextOrientation.horizontal,
        ),
      );
      final PsdTypeTool edited = _typeTool('Ancien').withText('Nouveau');

      expect(_engineTextTerminator(generated.engineData!), 13);
      expect(_engineTextTerminator(edited.engineData!), 13);
      expect(generated.content.text, 'Bonjour');
      expect(edited.content.text, 'Nouveau');
    });

    test('round-trips complete text semantics and independent descriptor bounds', () {
      final PsdTextColor fillColor = PsdTextColor.cmyk(
        alpha: 230,
        cyan: 10,
        magenta: 20,
        yellow: 30,
        black: 40,
      );
      final PsdTypeTool source = PsdTypeTool.fromText(
        content: PsdTextContent(
          text: 'Texte complet',
          orientation: PsdTextOrientation.vertical,
          antiAlias: PsdTextAntiAlias.platformLcd,
          gridding: PsdTextGridding.round,
          useFractionalGlyphWidths: false,
          shapeType: PsdTextShapeType.box,
          boxBounds: const PsdTextBox(left: 1.5, top: 2.5, right: 201.5, bottom: 82.5),
          gridInfo: const PsdTextGridInfo(
            isOn: true,
            show: true,
            size: 16,
            leading: 19.2,
            alignLineHeightToGrid: true,
          ),
          superscriptSize: 0.6,
          superscriptPosition: 0.4,
          subscriptSize: 0.55,
          subscriptPosition: 0.25,
          smallCapSize: 0.75,
          styleRuns: <PsdTextStyleRun>[
            PsdTextStyleRun(
              start: 0,
              length: 13,
              style: PsdTextStyle(
                font: const PsdTextFont(
                  name: 'Inter-Bold',
                  script: 1,
                  fontType: 2,
                  synthetic: 3,
                ),
                fontSize: 27,
                color: fillColor,
                strokeColor: const PsdTextColor.grayscale(alpha: 200, value: 96),
                tracking: 25,
                lineHeight: 31,
                automaticLeading: false,
                horizontalScale: 0.9,
                verticalScale: 1.1,
                automaticKerning: false,
                kerning: -15,
                baselineShift: 2,
                fontCaps: 2,
                fontBaseline: 1,
                fauxBold: true,
                fauxItalic: true,
                underline: true,
                strikethrough: true,
                ligatures: false,
                discretionaryLigatures: true,
                baselineDirection: 1,
                tsume: 0.2,
                styleRunAlignment: 1,
                language: 14,
                noBreak: true,
                fillEnabled: true,
                strokeEnabled: true,
                fillFirst: false,
                underlinePosition: 0,
                outlineWidth: 2.5,
                characterDirection: 1,
                hindiNumbers: true,
                kashida: 2,
                diacriticPosition: 1,
              ),
            ),
          ],
          paragraphs: const <PsdTextParagraph>[
            PsdTextParagraph(
              start: 0,
              length: 13,
              justification: PsdTextJustification.justifyAll,
              firstLineIndent: 4,
              startIndent: 5,
              endIndent: 6,
              spaceBefore: 7,
              spaceAfter: 8,
              automaticHyphenation: false,
              hyphenatedWordSize: 7,
              preHyphen: 3,
              postHyphen: 4,
              consecutiveHyphens: 5,
              zone: 42,
              wordSpacing: PsdTextSpacing(minimum: 0.7, desired: 1.1, maximum: 1.4),
              letterSpacing: PsdTextSpacing(minimum: -0.1, desired: 0.1, maximum: 0.2),
              glyphSpacing: PsdTextSpacing(minimum: 0.9, desired: 1, maximum: 1.2),
              automaticLeading: 1.3,
              leadingType: 1,
              hanging: true,
              burasagari: true,
              kinsokuOrder: 2,
              everyLineComposer: true,
              adjustments: PsdTextParagraphAdjustments(
                axis: <double>[1, 2, 3],
                xy: <double>[4, 5],
              ),
            ),
          ],
        ),
        bounds: const PsdTextBounds(left: -72.8878, top: -20.9251, right: 72.8878, bottom: 126.1177),
        descriptorBounds: PsdTextDescriptorBounds.pixels(left: 10, top: 20, right: 210, bottom: 120),
        boundingBox: const PsdTextDescriptorBounds(
          left: PsdTextUnitValue(unit: '#Pnt', value: 11),
          top: PsdTextUnitValue(unit: '#Pnt', value: 21),
          right: PsdTextUnitValue(unit: '#Pnt', value: 211),
          bottom: PsdTextUnitValue(unit: '#Pnt', value: 121),
        ),
        warp: const PsdTextWarp(
          style: PsdTextWarpStyle.arc,
          value: 50,
          perspective: 3,
          perspectiveOther: -4,
          rotation: PsdTextOrientation.vertical,
        ),
        textIndex: 7,
      );

      final Uint8List bytes = PsdTypeToolCodec.encode(source);
      final PsdTypeTool decoded = PsdTypeToolCodec.decode(bytes);
      final PsdTextContent content = decoded.content;
      final PsdTextStyle style = content.styleRuns.single.style;
      final PsdTextParagraph paragraph = content.paragraphs.single;

      expect(PsdTypeToolCodec.encode(decoded), orderedEquals(bytes));
      expect(decoded.bounds.left, closeTo(-72.8878, 0.00001));
      expect(decoded.descriptorBounds?.left.value, 10);
      expect(decoded.boundingBox?.left.unit, '#Pnt');
      expect(decoded.textIndex, 7);
      expect(decoded.warp.style, PsdTextWarpStyle.arc);
      expect(decoded.warp.value, 50);
      expect(content.antiAlias, PsdTextAntiAlias.platformLcd);
      expect(content.gridding, PsdTextGridding.round);
      expect(content.useFractionalGlyphWidths, isFalse);
      expect(content.shapeType, PsdTextShapeType.box);
      expect(content.hasShapeMetadata, isTrue);
      expect(content.boxBounds.right, 201.5);
      expect(content.gridInfo.alignLineHeightToGrid, isTrue);
      expect(content.superscriptSize, 0.6);
      expect(style.font?.name, 'Inter-Bold');
      expect(style.font?.fontType, 2);
      expect(style.color?.colorSpace, PsdTextColorSpace.cmyk);
      expect(style.color?.cyan, 10);
      expect(style.strokeColor?.colorSpace, PsdTextColorSpace.grayscale);
      expect(style.strokeColor?.gray, 96);
      expect(style.automaticLeading, isFalse);
      expect(style.lineHeight, 31);
      expect(style.underline, isTrue);
      expect(style.strikethrough, isTrue);
      expect(style.discretionaryLigatures, isTrue);
      expect(style.strokeEnabled, isTrue);
      expect(style.hindiNumbers, isTrue);
      expect(paragraph.justification, PsdTextJustification.justifyAll);
      expect(paragraph.spaceAfter, 8);
      expect(paragraph.automaticHyphenation, isFalse);
      expect(paragraph.wordSpacing.maximum, 1.4);
      expect(paragraph.adjustments.axis, orderedEquals(<double>[1, 2, 3]));
      expect(String.fromCharCodes(decoded.engineData!), contains('/DocumentResources'));
      expect(String.fromCharCodes(decoded.engineData!), contains('/Rendered'));
    });

    test('uses EngineData antialiasing when the descriptor omits it', () {
      final PsdTypeTool typeTool = _typeTool(
        'Salut',
        engineAntiAlias: 3,
      );

      expect(typeTool.antiAlias, PsdTextAntiAlias.sharp);
      expect(typeTool.content.antiAlias, PsdTextAntiAlias.smooth);
    });

    test('distinguishes unknown warp styles from an explicit no-warp value', () {
      final PsdTypeTool source = _typeTool('Salut');
      final PsdTypeTool unknown = PsdTypeTool(
        textDescriptor: source.textDescriptor,
        warpDescriptor: source.warpDescriptor.withValue(
          'warpStyle',
          const PsEnumeratedValue(
            typeId: 'warpStyle',
            value: 'futureWarpStyle',
          ),
        ),
      );

      expect(unknown.warp.style, PsdTextWarpStyle.custom);
    });

    test('resolves inherited styles and Boolean decoration values', () {
      final PsdTextContent content = PsdTextEngine.decode(
        _inheritedEngineData(),
        fallbackText: 'A',
        orientation: PsdTextOrientation.horizontal,
      );
      final PsdTextStyle style = content.styleRuns.single.style;

      expect(style.fontFamily, 'Inherited-Regular');
      expect(style.fontSize, 21);
      expect(style.color?.colorSpace, PsdTextColorSpace.grayscale);
      expect(style.color?.gray, 128);
      expect(style.underline, isTrue);
      expect(style.strikethrough, isTrue);
      expect(style.automaticKerning, isFalse);
    });

    test('round-trips the published Photoshop 5.x type-tool structure', () {
      final PsdLegacyTypeTool source = PsdLegacyTypeTool(
        transform: const PsdTextTransform(xx: 1, xy: 0.1, yx: -0.2, yy: 1, tx: 12, ty: 34),
        faces: <PsdLegacyTextFace>[
          PsdLegacyTextFace(
            mark: 3,
            fontType: 1,
            fontName: 'LegacyPS',
            fontFamilyName: 'Legacy',
            fontStyleName: 'Bold',
            script: 0,
            designVector: const <int>[100, 200],
          ),
        ],
        styles: const <PsdLegacyTextStyle>[
          PsdLegacyTextStyle(
            mark: 4,
            faceMark: 3,
            size: 12000,
            tracking: 20,
            kerning: -10,
            leading: 14000,
            baselineShift: 2,
            automaticKerning: true,
            compatibilityByte: 0x7f,
            rotate: false,
          ),
        ],
        type: 1,
        scalingFactor: 1000,
        characterCount: 5,
        horizontalPlacement: 10,
        verticalPlacement: 20,
        selectionStart: 1,
        selectionEnd: 4,
        lines: const <PsdLegacyTextLine>[
          PsdLegacyTextLine(
            characterCount: 5,
            orientation: 0,
            alignment: 2,
            actualCharacter: 0x41,
            style: 4,
          ),
        ],
        color: PsdLegacyTextColor(
          colorSpace: 0,
          components: const <int>[0xffff, 0x8000, 0x4000, 0],
        ),
        antiAlias: true,
        trailingData: Uint8List.fromList(<int>[9, 8, 7]),
      );

      final Uint8List bytes = PsdLegacyTypeToolCodec.encode(source);
      final PsdLegacyTypeTool decoded = PsdLegacyTypeToolCodec.decode(bytes);
      final PsdLayer layer = PsdLayer(
        rectangle: const PsdRectangle(top: 0, left: 0, bottom: 1, right: 1),
        name: 'Legacy',
      ).withLegacyTypeTool(decoded);

      expect(PsdLegacyTypeToolCodec.encode(decoded), orderedEquals(bytes));
      expect(decoded.faces.single.fontName, 'LegacyPS');
      expect(decoded.faces.single.designVector, orderedEquals(<int>[100, 200]));
      expect(decoded.styles.single.automaticKerning, isTrue);
      expect(decoded.lines.single.actualCharacter, 0x41);
      expect(decoded.color.components, orderedEquals(<int>[0xffff, 0x8000, 0x4000, 0]));
      expect(decoded.trailingData, orderedEquals(<int>[9, 8, 7]));
      expect(layer.legacyTypeTool?.faces.single.fontFamilyName, 'Legacy');
      expect(layer.withTypeTool(_typeTool('Modern')).legacyTypeTool, isNull);
    });

    test('exposes document-level Txt2 data as an immutable structure', () {
      final Uint8List bytes = Uint8List.fromList(
        '<< /ResourceDict << /FontSet [ /AdobeInvisFont ] >> /EngineDict << >> >>'.codeUnits,
      );
      final PsdDocument source = PsdDocument(
        width: 1,
        height: 1,
        channels: 3,
        depth: 8,
        colorMode: PsdColorMode.rgb,
        mergedImage: <Uint8List>[
          for (int index = 0; index < 3; index++) Uint8List.fromList(<int>[0]),
        ],
      ).withGlobalTextEngineData(PsdGlobalTextEngineData(data: bytes));

      final PsdGlobalTextEngineData engineData = source.globalTextEngineData!;
      final Map<String, Object?> structure = engineData.structure! as Map<String, Object?>;
      final Map<String, Object?> resources = structure['ResourceDict']! as Map<String, Object?>;
      final List<Object?> fonts = resources['FontSet']! as List<Object?>;

      expect(engineData.data, orderedEquals(bytes));
      expect((fonts.single as PsdTextEngineName).value, 'AdobeInvisFont');
      expect(() => structure['Other'] = 1, throwsUnsupportedError);
      expect(source.withGlobalTextEngineData(null).globalTextEngineData, isNull);
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

    test('rejects deeply nested engine data instead of exhausting the stack', () {
      const int depth = 100000;
      final Map<String, Uint8List> hostile = <String, Uint8List>{
        'dictionaries': Uint8List.fromList(('${'<< /Nested ' * depth}<< >>${' >>' * depth}').codeUnits),
        'arrays': Uint8List.fromList(('${'[' * depth}${']' * depth}').codeUnits),
      };

      for (final MapEntry<String, Uint8List> entry in hostile.entries) {
        final PsdTextContent content = PsdTextEngine.decode(
          entry.value,
          fallbackText: 'Secours',
          orientation: PsdTextOrientation.horizontal,
        );

        expect(content.text, 'Secours', reason: entry.key);
        expect(content.styleRuns, isEmpty, reason: entry.key);
      }
    });
  });
}

/// Builds a representative type-tool payload containing [text].
PsdTypeTool _typeTool(
  String text, {
  bool terminalParagraphMark = false,
  int? engineAntiAlias,
}) => PsdTypeTool(
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
        value: PsRawValue(
          value: _engineData(
            text,
            terminalParagraphMark: terminalParagraphMark,
            antiAlias: engineAntiAlias,
          ),
        ),
      ),
    ],
  ),
  warpDescriptor: const PsDescriptor(name: '', classId: 'warp'),
  bounds: const PsdTextBounds(left: 0, top: 0, right: 100, bottom: 40),
  trailingData: Uint8List.fromList(<int>[0, 0]),
);

/// Builds minimal Photoshop text-engine data containing [text].
Uint8List _engineData(
  String text, {
  bool terminalParagraphMark = false,
  int? antiAlias,
}) {
  final String encodedText = terminalParagraphMark ? '$text\r' : text;
  final BytesBuilder bytes = BytesBuilder(copy: false)
    ..add(
      '''<< /EngineDict <<
/Editor << /Text ('''
          .codeUnits,
    )
    ..add(_utf16(encodedText))
    ..add(
      ''') >>
${antiAlias == null ? '' : '/AntiAlias $antiAlias'}
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

/// Returns the last UTF-16 code unit in the EngineData editor string.
int? _engineTextTerminator(Uint8List data) {
  final List<int> marker = '/Text ('.codeUnits;
  int start = -1;
  for (int index = 0; index <= data.length - marker.length; index++) {
    bool matches = true;
    for (int markerIndex = 0; markerIndex < marker.length; markerIndex++) {
      if (data[index + markerIndex] != marker[markerIndex]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      start = index + marker.length;
      break;
    }
  }
  if (start < 0) {
    return null;
  }
  int closing = start;
  while (closing < data.length) {
    if (data[closing] == 0x5c) {
      closing += 2;
    } else if (data[closing] == 0x29) {
      break;
    } else {
      closing++;
    }
  }
  if (closing < start + 4) {
    return null;
  }
  return data[closing - 2] << 8 | data[closing - 1];
}

/// Builds EngineData whose character run inherits its font and color.
Uint8List _inheritedEngineData() {
  final BytesBuilder bytes = BytesBuilder(copy: false)
    ..add('<< /EngineDict << /Editor << /Text ('.codeUnits)
    ..add(_utf16('A\r'))
    ..add(
      ''') >>
/StyleRun << /DefaultRunData << /StyleSheet << /StyleSheetData << >> >> >>
/RunArray [ << /StyleSheet << /DefaultStyleSheet 0 /StyleSheetData <<
/AutoKerning false /Underline true /Strikethrough 1
>> >> >> ] /RunLengthArray [ 2 ] >>
/ParagraphRun << /RunArray [ << /ParagraphSheet << /DefaultStyleSheet 0
/Properties << /Justification 0 >> >> >> ] /RunLengthArray [ 2 ] >>
>> /ResourceDict << /TheNormalStyleSheet 0 /StyleSheetSet [ <<
/StyleSheetData << /Font 0 /FontSize 21
/FillColor << /Type 0 /Values [ 1 0.5019607843137255 ] >>
>> >> ] /FontSet [ << /Name ('''
          .codeUnits,
    )
    ..add(_utf16('Inherited-Regular'))
    ..add(') /Script 0 /FontType 1 /Synthetic 0 >> ] >> >>'.codeUnits);
  return bytes.takeBytes();
}
