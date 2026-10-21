import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

import 'support/memory_output.dart';

/// Checks observed PSB keys whose length differs from the older published list.
void main() {
  for (final String key in ['lnk3', 'lnkE', 'pths', 'extd', 'extn', 'FELS', 'cinf', 'artd']) {
    for (final PsdVersion version in PsdVersion.values) {
      for (final String signature in ['8BIM', '8B64']) {
        test('${version.name} $signature $key uses the container-specific length', () async {
          final Uint8List payload = Uint8List.fromList([23, 42, 57, 81]);
          final PsdDocument source = PsdDocument(
            version: version,
            width: 1,
            height: 1,
            channels: 1,
            depth: 8,
            colorMode: PsdColorMode.grayscale,
            mergedImage: [Uint8List(1)],
            additionalLayerInfo: [PsdTaggedBlock(signature: signature, key: key, data: payload)],
          );
          final Uint8List bytes = PsdCodec.encode(source);
          final PsBinaryReader reader = PsBinaryReader(bytes: bytes)..skip(26);
          reader.skip(reader.readUint32()); // Color-mode data.
          reader.skip(reader.readUint32()); // Resources.
          final PsBinaryReader section = reader.readReader(version == PsdVersion.psb ? reader.readUint64() : reader.readUint32());
          section.skip(version == PsdVersion.psb ? section.readUint64() : section.readUint32());
          section.skip(section.readUint32()); // Global mask.
          expect(section.readString(4), signature);
          expect(section.readString(4), key);
          if (version == PsdVersion.psb) {
            expect(section.readUint32(), 0); // High half of the 64-bit length.
          }
          expect(section.readUint32(), payload.length);
          expect(section.readBytes(payload.length), payload);
          expect(section.remaining, 0);
          expect(PsdCodec.decode(bytes).additionalLayerInfo.single.data, payload);
          final MemoryRandomAccessOutput output = MemoryRandomAccessOutput();
          await PsdCodec.encodeTo(PsdStreamDocument.fromDocument(source), output);
          expect(output.bytes, bytes);
        });
      }
    }
  }
}
