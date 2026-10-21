import 'dart:typed_data';

import 'package:pscore/pscore.dart';

part 'text/content.dart';
part 'text/descriptors.dart';
part 'text/engine_decoder.dart';
part 'text/engine_editor.dart';
part 'text/engine_encoder.dart';
part 'text/engine_parser.dart';
part 'text/engine_runs.dart';
part 'text/legacy_type_tool.dart';
part 'text/paragraphs.dart';
part 'text/styles.dart';
part 'text/type_tool.dart';

/// A slash-prefixed PostScript name found in decoded Adobe text-engine data.
final class PsdTextEngineName {
  /// Name without its leading slash.
  final String value;

  /// Creates a decoded text-engine name.
  const PsdTextEngineName({required this.value});
}

/// Document-level Photoshop `Txt2` text-engine data.
final class PsdGlobalTextEngineData {
  /// Original text-engine bytes.
  final Uint8List data;

  /// Creates document-level text-engine data.
  PsdGlobalTextEngineData({required Uint8List data}) : data = Uint8List.fromList(data);

  /// Decodes the PostScript-like payload into maps, lists, values, and names.
  Object? get structure => PsdTextEngine.decodeStructure(data);

  /// Decodes [structure], returning `null` when the payload is malformed.
  Object? get tryStructure {
    try {
      return structure;
    } on FormatException {
      return null;
    }
  }
}

/// Parses and updates Adobe text-engine data without normalizing unknown keys.
abstract final class PsdTextEngine {
  /// Decodes arbitrary Adobe text-engine data into immutable Dart values.
  ///
  /// Dictionaries become maps, arrays become lists, binary text strings become
  /// Dart strings, and slash-prefixed values become [PsdTextEngineName] objects.
  static Object? decodeStructure(Uint8List engineData) => _publicEngineValue(
    _PsdEngineParser(bytes: engineData).parse(),
  );

  /// Extracts semantic text information from opaque Adobe [engineData].
  static PsdTextContent decode(
    Uint8List? engineData, {
    required String fallbackText,
    required PsdTextOrientation orientation,
    PsdTextAntiAlias fallbackAntiAlias = PsdTextAntiAlias.sharp,
    PsdTextAntiAlias? antiAliasOverride,
    PsdTextGridding gridding = PsdTextGridding.none,
  }) => _decodeTextEngine(
    engineData,
    fallbackText: fallbackText,
    orientation: orientation,
    fallbackAntiAlias: fallbackAntiAlias,
    antiAliasOverride: antiAliasOverride,
    gridding: gridding,
  );

  /// Encodes semantic [content] as self-contained Adobe text-engine data.
  static Uint8List encode(PsdTextContent content) => _encodeTextEngine(content);

  /// Replaces the PostScript string assigned to `/Text` in [engineData].
  static Uint8List replaceText(Uint8List engineData, String text) => _replaceEngineText(engineData, text);
}
