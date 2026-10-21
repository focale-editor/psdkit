part of '../codec.dart';

/// Tagged blocks whose payload length expands to 64 bits in PSB files.
const Set<String> _widePsbTaggedBlocks = <String>{
  'LMsk',
  'Lr16',
  'Lr32',
  'Layr',
  'Mt16',
  'Mt32',
  'Mtrn',
  'Alph',
  'FMsk',
  'lnk2',
  'FEid',
  'FXid',
  'PxSD',
};

/// Reads aligned additional-layer-information blocks to the bounded end.
List<PsdTaggedBlock> _readTaggedBlocks(PsBinaryReader reader, PsdVersion version) {
  final List<PsdTaggedBlock> result = <PsdTaggedBlock>[];
  while (reader.remaining >= 12) {
    _skipTaggedPadding(reader);
    if (reader.remaining < 12) {
      break;
    }
    final PsTaggedBlockHeader header = PsTaggedBlockCodec.readHeader(
      reader,
      signatures: _tiffSignatures,
      wideLengthResolver: (signature, key) => version == PsdVersion.psb && _widePsbTaggedBlocks.contains(key),
    );
    final Uint8List data = reader.readBytes(header.declaredLength);
    if (header.declaredLength.isOdd) {
      reader.skip(1);
    }
    result.add(
      PsdTaggedBlock(
        key: header.key,
        signature: header.signature,
        data: data,
      ),
    );
  }
  if (reader.remaining != 0) {
    final Uint8List padding = reader.readBytes(reader.remaining);
    if (padding.any((value) => value != 0)) {
      throw const PsFormatException(message: 'Non-zero trailing bytes after tagged blocks');
    }
  }
  return result;
}

/// Skips up to three zero bytes used by writers that align tagged blocks to four bytes.
void _skipTaggedPadding(PsBinaryReader reader) {
  for (int padding = 1; padding <= 3 && reader.remaining >= padding + 4; padding++) {
    final bool zeros = Uint8List.sublistView(reader.bytes, reader.offset, reader.offset + padding).every((value) => value == 0);
    final String signature = String.fromCharCodes(Uint8List.sublistView(reader.bytes, reader.offset + padding, reader.offset + padding + 4));
    if (zeros && _tiffSignatures.contains(signature)) {
      reader.skip(padding);
      return;
    }
  }
}

/// Returns [layer]'s tagged blocks with a `luni` block naming it, when it needs one.
///
/// A stored block that already holds the name is kept byte for byte and in
/// place, as is the absence of one in a layer read without it.
List<PsdTaggedBlock> _layerBlocksWithName(PsdLayer layer) {
  final bool hasUnicodeName = layer.additionalInfo.any((block) => block.key == 'luni');
  if (hasUnicodeName) {
    String? stored;
    try {
      stored = _unicodeLayerName(layer.additionalInfo);
    } on FormatException {
      stored = null;
    }
    if (stored == layer.name) {
      return layer.additionalInfo;
    }
    final PsdTaggedBlock renamed = PsdTaggedBlock(key: 'luni', data: _writeUnicodeString(layer.name));
    return <PsdTaggedBlock>[
      for (final PsdTaggedBlock block in layer.additionalInfo)
        if (block.key == 'luni') renamed else block,
    ];
  }
  final bool asciiName = layer.name.length <= 255 && layer.name.codeUnits.every((unit) => unit < 0x80);
  if (!layer.writesUnicodeName && asciiName) {
    return layer.additionalInfo;
  }
  return <PsdTaggedBlock>[...layer.additionalInfo, PsdTaggedBlock(key: 'luni', data: _writeUnicodeString(layer.name))];
}

/// Serializes [blocks] with version-specific lengths and even-byte padding.
Uint8List _writeTaggedBlocks(List<PsdTaggedBlock> blocks, PsdVersion version) {
  final PsBinaryWriter writer = PsBinaryWriter();
  for (final PsdTaggedBlock block in blocks) {
    PsTaggedBlockCodec.write(
      writer,
      PsTaggedBlock(
        signature: block.signature,
        key: block.key,
        data: block.data,
      ),
      wideLengthResolver: (signature, key) => version == PsdVersion.psb && _widePsbTaggedBlocks.contains(key),
      alignment: 2,
    );
  }
  return writer.takeBytes();
}

/// Decodes the last well-formed Unicode layer-name block, when present.
String? _unicodeLayerName(List<PsdTaggedBlock> blocks) {
  for (final PsdTaggedBlock block in blocks.reversed) {
    if (block.key != 'luni' || block.data.length < 4) {
      continue;
    }
    final PsBinaryReader reader = PsBinaryReader(bytes: block.data);
    final int units = reader.readUint32();
    if (units > reader.remaining ~/ 2) {
      throw const PsFormatException(message: 'Truncated Unicode layer name');
    }
    final List<int> codeUnits = <int>[for (int index = 0; index < units; index++) reader.readUint16()];
    return String.fromCharCodes(codeUnits);
  }
  return null;
}

/// Encodes [value] as a length-prefixed big-endian UTF-16 string.
Uint8List _writeUnicodeString(String value) {
  final PsBinaryWriter writer = PsBinaryWriter()..writeUint32(value.codeUnits.length);
  value.codeUnits.forEach(writer.writeUint16);
  return writer.takeBytes();
}

/// Encodes the required legacy one-byte name, replacing unsupported units.
Uint8List _legacyName(String value) {
  final List<int> bytes = <int>[];
  for (final int unit in value.codeUnits.take(255)) {
    bytes.add(unit <= 0xff ? unit : 0x3f);
  }
  return Uint8List.fromList(bytes);
}
