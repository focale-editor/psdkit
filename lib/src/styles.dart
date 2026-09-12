import 'dart:typed_data';

import 'package:aslkit/aslkit.dart' as asl;
import 'package:pscore/pscore.dart';
import 'package:psdkit/src/effects.dart';
import 'package:psdkit/src/layer_comps.dart';

/// One loss-preserving Photoshop layer-style preset.
final class PsdStylePreset {
  /// Descriptor containing the preset name and stable identifier.
  final PsDescriptor identityDescriptor;

  /// Descriptor containing effects and optional layer blending options.
  final PsDescriptor styleDescriptor;

  /// Uninterpreted bytes following the two descriptors inside this record.
  final Uint8List trailingData;

  /// Creates one preset from complete Photoshop descriptors.
  PsdStylePreset({
    required this.identityDescriptor,
    required this.styleDescriptor,
    Uint8List? trailingData,
  }) : trailingData = _immutableBytes(trailingData);

  /// Creates a Photoshop-compatible preset from semantic effects.
  factory PsdStylePreset.create({
    required String id,
    required String name,
    required PsdLayerEffects effects,
    PsdLayerCompBlendOptions? blendingOptions,
  }) {
    if (id.isEmpty || id.length > PsdStyleLibraryCodec.maximumIdentifierLength) {
      throw const PsWriteException(message: 'ASL style identifier is invalid');
    }
    if (name.isEmpty || name.length > PsdStyleLibraryCodec.maximumNameLength) {
      throw const PsWriteException(message: 'ASL style name is invalid');
    }
    final PsDescriptor effectDescriptor = PsDescriptor(
      name: effects.descriptor.name,
      classId: 'Lefx',
      items: effects.descriptor.items,
    );
    return PsdStylePreset(
      identityDescriptor: PsDescriptor(
        name: '\u0000',
        classId: 'null',
        items: [
          PsDescriptorItem(
            key: 'Nm  ',
            value: PsStringValue(value: name),
          ),
          PsDescriptorItem(
            key: 'Idnt',
            value: PsStringValue(value: id),
          ),
        ],
      ),
      styleDescriptor: PsDescriptor(
        name: '\u0000',
        classId: 'Styl',
        items: [
          const PsDescriptorItem(
            key: 'documentMode',
            value: PsObjectValue(
              value: PsDescriptor(
                name: '\u0000',
                classId: 'documentMode',
              ),
            ),
          ),
          PsDescriptorItem(
            key: 'Lefx',
            value: PsObjectValue(value: effectDescriptor),
          ),
          if (blendingOptions != null)
            PsDescriptorItem(
              key: 'blendOptions',
              value: PsObjectValue(value: blendingOptions.descriptor),
            ),
        ],
      ),
    );
  }

  /// User-visible name, resolving Photoshop's localized ZString notation.
  String get name => _resolveZString(_descriptorString(identityDescriptor, 'Nm  '));

  /// Stable identifier stored by Photoshop, or an empty string when absent.
  String get id => _descriptorString(identityDescriptor, 'Idnt');

  /// Editable effects represented by the preset, when present.
  PsdLayerEffects? get effects => switch (styleDescriptor.value('Lefx')) {
    PsObjectValue(:final PsDescriptor value) => PsdLayerEffects(descriptor: value),
    _ => null,
  };

  /// Optional opacity, blend mode, fill opacity, and Blend If descriptor.
  PsdLayerCompBlendOptions? get blendingOptions => switch (styleDescriptor.value('blendOptions')) {
    PsObjectValue(:final PsDescriptor value) => PsdLayerCompBlendOptions(descriptor: value),
    _ => null,
  };
}

/// A decoded Photoshop ASL library with its embedded pattern section.
final class PsdStyleLibrary {
  /// Version of the embedded Photoshop pattern block.
  final int patternsVersion;

  /// Complete embedded pattern-block payload, preserved losslessly.
  final Uint8List patternsData;

  /// Style presets in file order.
  final List<PsdStylePreset> styles;

  /// Bytes following the counted style records, such as `8BIMphry` metadata.
  final Uint8List trailingData;

  /// Creates one immutable decoded style library.
  PsdStyleLibrary({
    this.patternsVersion = 3,
    Uint8List? patternsData,
    required List<PsdStylePreset> styles,
    Uint8List? trailingData,
  }) : patternsData = _immutableBytes(patternsData),
       styles = List<PsdStylePreset>.unmodifiable(styles),
       trailingData = _immutableBytes(trailingData);
}

/// Encodes and decodes Photoshop `.asl` style libraries.
abstract final class PsdStyleLibraryCodec {
  /// Largest ASL payload accepted from an untrusted source.
  static const int maximumBytes = 32 * 1024 * 1024;

  /// Largest style catalogue accepted from one file.
  static const int maximumStyleCount = 4096;

  /// Largest decoded style name accepted by the semantic convenience API.
  static const int maximumNameLength = 4096;

  /// Largest decoded Photoshop style identifier.
  static const int maximumIdentifierLength = 255;

  /// Decodes one complete ASL file.
  static PsdStyleLibrary decode(Uint8List bytes) {
    if (bytes.length > maximumBytes) {
      throw const PsFormatException(message: 'ASL file exceeds the supported byte limit');
    }
    try {
      final asl.AslFile file = asl.AslDecoder.decode(
        bytes,
        options: const asl.AslDecodeOptions(
          mode: asl.AslDecodeMode.tolerant,
          maxFileBytes: maximumBytes,
          maxPatternSectionBytes: maximumBytes,
          maxPatternBytes: maximumBytes,
          maxDecodedPixelBytes: maximumBytes,
          maxStyles: maximumStyleCount,
          maxStyleBytes: maximumBytes,
          maxTaggedBlockBytes: maximumBytes,
          decodePatternChannelData: false,
          preservePatternChannelData: false,
          preservePatternRecordData: false,
          preserveTaggedBlockData: false,
          preserveTrailingData: false,
          preserveSourceData: false,
        ),
      );
      if (file.containerKind != asl.AslContainerKind.styleLibrary || file.version != 2 || file.styles.length != file.declaredStyleCount) {
        throw PsFormatException(
          message: 'Unsupported or incomplete Photoshop style-library envelope',
          source: bytes,
          offset: 0,
        );
      }
      final List<PsdStylePreset> styles = <PsdStylePreset>[];
      for (final asl.AslStyle style in file.styles) {
        final PsDescriptor? identity = style.identificationDescriptor;
        final PsDescriptor? information = style.styleDescriptor;
        if (identity == null || information == null || style.identificationDescriptorVersion != 16 || style.styleDescriptorVersion != 16) {
          throw PsFormatException(
            message: 'Unsupported or malformed ASL style descriptor pair',
            source: bytes,
            offset: style.sourceOffset,
          );
        }
        final PsdStylePreset preset = PsdStylePreset(
          identityDescriptor: identity,
          styleDescriptor: information,
          trailingData: style.recordTrailingData,
        );
        if (preset.name.length > maximumNameLength || preset.id.length > maximumIdentifierLength) {
          throw PsFormatException(
            message: 'ASL style metadata exceeds the supported text limit',
            source: bytes,
            offset: style.sourceOffset,
          );
        }
        styles.add(preset);
      }
      const int patternOffset = 12;
      final int patternEnd = patternOffset + file.declaredPatternSectionLength;
      final int trailingOffset = file.styles.isEmpty ? patternEnd + 4 : file.styles.last.sourceOffset + 4 + file.styles.last.declaredLength + file.styles.last.paddingData.length;
      return PsdStyleLibrary(
        patternsVersion: file.patternsVersion,
        patternsData: Uint8List.sublistView(bytes, patternOffset, patternEnd),
        styles: styles,
        trailingData: Uint8List.sublistView(bytes, trailingOffset),
      );
    } on asl.AslFormatException catch (error) {
      throw PsFormatException(
        message: error.message,
        source: bytes,
        offset: error.offset,
      );
    }
  }

  /// Encodes one complete ASL file deterministically.
  static Uint8List encode(PsdStyleLibrary library) {
    if (library.styles.length > maximumStyleCount) {
      throw const PsWriteException(message: 'ASL style count exceeds the supported limit');
    }
    if (library.patternsData.length + library.trailingData.length > maximumBytes) {
      throw const PsWriteException(message: 'ASL file exceeds the supported byte limit');
    }
    for (final PsdStylePreset style in library.styles) {
      if (style.name.length > maximumNameLength || style.id.length > maximumIdentifierLength) {
        throw const PsWriteException(message: 'ASL style metadata exceeds the supported text limit');
      }
    }
    try {
      final asl.AslFile file = asl.AslFile(
        containerKind: asl.AslContainerKind.styleLibrary,
        version: 2,
        signature: '8BSL',
        patternsVersion: library.patternsVersion,
        declaredPatternSectionLength: library.patternsData.length,
        patternRecords: const <asl.AslPatternRecord>[],
        patternSectionTrailingData: library.patternsData,
        patternSectionTrailingByteCount: library.patternsData.length,
        declaredStyleCount: library.styles.length,
        styles: <asl.AslStyle>[
          for (int index = 0; index < library.styles.length; index++)
            asl.AslStyle(
              index: index,
              sourceOffset: 0,
              declaredLength: 0,
              identificationDescriptorVersion: 16,
              identificationDescriptor: library.styles[index].identityDescriptor,
              styleDescriptorVersion: 16,
              styleDescriptor: library.styles[index].styleDescriptor,
              serializedName: library.styles[index].name,
              name: library.styles[index].name,
              id: library.styles[index].id,
              documentMode: null,
              layerEffects: null,
              blendOptions: null,
              recordTrailingData: library.styles[index].trailingData,
              paddingData: Uint8List(0),
              recordData: null,
              decodeError: null,
            ),
        ],
        hierarchy: const <asl.AslHierarchyEntry>[],
        hierarchyDescriptors: const <PsDescriptor>[],
        taggedBlocks: const <asl.AslTaggedBlock>[],
        trailingData: library.trailingData,
        trailingByteCount: library.trailingData.length,
        warnings: const <asl.AslWarning>[],
        decodedPixelBytes: 0,
        sourceData: null,
      );
      final Uint8List encoded = asl.AslEncoder.encode(
        file,
        options: const asl.AslEncodeOptions(mode: asl.AslEncodeMode.permissive),
      );
      if (encoded.length > maximumBytes) {
        throw const PsWriteException(message: 'ASL file exceeds the supported byte limit');
      }
      return encoded;
    } on asl.AslWriteException catch (error) {
      throw PsWriteException(message: error.message);
    }
  }
}

/// Reads one descriptor text value without coercing another value type.
String _descriptorString(PsDescriptor descriptor, String key) => descriptor.stringValue(key) ?? '';

/// Resolves Photoshop's `$$$/key=Display name` localization notation.
String _resolveZString(String value) {
  if (!value.startsWith(r'$$$/')) {
    return value;
  }
  final int equals = value.indexOf('=');
  if (equals >= 0 && equals + 1 < value.length) {
    return value.substring(equals + 1);
  }
  final int slash = value.lastIndexOf('/');
  return slash < 0 ? value : value.substring(slash + 1);
}

/// Returns an unmodifiable copy of optional caller-owned bytes.
Uint8List _immutableBytes(Uint8List? bytes) => Uint8List.fromList(
  bytes ?? Uint8List(0),
).asUnmodifiableView();
