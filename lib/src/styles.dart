import 'dart:typed_data';

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
  }) : trailingData = trailingData ?? Uint8List(0);

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
  }) : patternsData = patternsData ?? Uint8List(0),
       styles = List<PsdStylePreset>.unmodifiable(styles),
       trailingData = trailingData ?? Uint8List(0);
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
    final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
    final int version = reader.readUint16();
    if (version != 2 || reader.readString(4) != '8BSL') {
      throw PsFormatException(
        message: 'Unsupported Photoshop style-library header',
        source: bytes,
        offset: 0,
      );
    }
    final int patternsVersion = reader.readUint16();
    final int patternsLength = reader.readUint32();
    if (patternsLength > reader.remaining) {
      throw PsFormatException(
        message: 'ASL pattern section is truncated',
        source: bytes,
        offset: reader.offset,
      );
    }
    final Uint8List patternsData = reader.readBytes(patternsLength);
    final int styleCount = reader.readUint32();
    if (styleCount > maximumStyleCount) {
      throw PsFormatException(
        message: 'ASL style count exceeds the supported limit',
        source: bytes,
        offset: reader.offset - 4,
      );
    }
    final List<PsdStylePreset> styles = [];
    for (int index = 0; index < styleCount; index++) {
      final int recordLength = reader.readUint32();
      if (recordLength > reader.remaining) {
        throw PsFormatException(
          message: 'ASL style record is truncated',
          source: bytes,
          offset: reader.offset,
        );
      }
      final PsBinaryReader record = reader.readReader(recordLength);
      if (record.readUint32() != 16) {
        throw PsFormatException(
          message: 'Unsupported ASL identity descriptor version',
          source: bytes,
          offset: record.baseOffset,
        );
      }
      final PsDescriptor identity = PsDescriptorCodec.decodeReader(record);
      if (record.readUint32() != 16) {
        throw PsFormatException(
          message: 'Unsupported ASL style descriptor version',
          source: bytes,
          offset: record.baseOffset + record.offset - 4,
        );
      }
      final PsDescriptor style = PsDescriptorCodec.decodeReader(record);
      final Uint8List trailingData = record.readBytes(record.remaining);
      final PsdStylePreset preset = PsdStylePreset(
        identityDescriptor: identity,
        styleDescriptor: style,
        trailingData: trailingData,
      );
      if (preset.name.length > maximumNameLength || preset.id.length > maximumIdentifierLength) {
        throw PsFormatException(
          message: 'ASL style metadata exceeds the supported text limit',
          source: bytes,
          offset: record.baseOffset,
        );
      }
      styles.add(preset);
      final int padding = _paddingFor(recordLength);
      if (padding > reader.remaining) {
        throw PsFormatException(
          message: 'ASL style record padding is truncated',
          source: bytes,
          offset: reader.offset,
        );
      }
      reader.skip(padding);
    }
    return PsdStyleLibrary(
      patternsVersion: patternsVersion,
      patternsData: patternsData,
      styles: styles,
      trailingData: reader.readBytes(reader.remaining),
    );
  }

  /// Encodes one complete ASL file deterministically.
  static Uint8List encode(PsdStyleLibrary library) {
    if (library.styles.length > maximumStyleCount) {
      throw const PsWriteException(message: 'ASL style count exceeds the supported limit');
    }
    final PsBinaryWriter writer = PsBinaryWriter()
      ..writeUint16(2)
      ..writeString('8BSL')
      ..writeUint16(library.patternsVersion)
      ..writeUint32(library.patternsData.length)
      ..writeBytes(library.patternsData)
      ..writeUint32(library.styles.length);
    for (final PsdStylePreset style in library.styles) {
      if (style.name.length > maximumNameLength || style.id.length > maximumIdentifierLength) {
        throw const PsWriteException(message: 'ASL style metadata exceeds the supported text limit');
      }
      final PsBinaryWriter record = PsBinaryWriter()
        ..writeUint32(16)
        ..writeBytes(PsDescriptorCodec.encode(style.identityDescriptor))
        ..writeUint32(16)
        ..writeBytes(PsDescriptorCodec.encode(style.styleDescriptor))
        ..writeBytes(style.trailingData);
      final int padding = _paddingFor(record.length);
      record.writeZeros(padding);
      final Uint8List recordBytes = record.takeBytes();
      writer
        ..writeUint32(recordBytes.length)
        ..writeBytes(recordBytes);
    }
    writer.writeBytes(library.trailingData);
    final Uint8List encoded = writer.takeBytes();
    if (encoded.length > maximumBytes) {
      throw const PsWriteException(message: 'ASL file exceeds the supported byte limit');
    }
    return encoded;
  }

  /// Returns the four-byte alignment padding following [length].
  static int _paddingFor(int length) => (4 - length % 4) % 4;
}

/// Reads one descriptor text value without coercing another value type.
String _descriptorString(PsDescriptor descriptor, String key) => switch (descriptor.value(key)) {
  PsStringValue(:final String value) => value.replaceFirst(RegExp(r'\u0000+$'), ''),
  _ => '',
};

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
