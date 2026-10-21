part of '../codec.dart';

/// Chooses a Photoshop-supported encoding without changing stored source samples.
PsdCompression _outputCompression(PsdCompression preferred, int depth, PsdWriteOptions options) {
  final PsdCompression selected = options.compression ?? preferred;
  return options.compatibility == PsdWriteCompatibility.photoshop && depth == 32 && selected == PsdCompression.rle ? PsdCompression.raw : selected;
}

/// Supplies Photoshop's default HDR records only when the caller has none.
Uint8List _outputColorModeData(PsdDocument document, PsdWriteOptions options) =>
    options.compatibility == PsdWriteCompatibility.photoshop && document.depth == 32 && document.colorModeData.isEmpty ? _defaultHdrToningData() : document.colorModeData;

/// Builds the 110-byte `hdrt` and `hdra` records observed in Photoshop exports.
///
/// Layout established by PhotoCraft's Photoshop corpus; see test/corpus/NOTICE.md.
/// Opaque values follow a fresh Photoshop document with its Linear toning curve.
Uint8List _defaultHdrToningData() =>
    (PsBinaryWriter()
          ..writeString('hdrt')
          ..writeUint32(3)
          ..writeFloat32(0.23)
          ..writeUint32(2)
          ..writeUint32(7)
          ..writeUint16List('Linear\u0000'.codeUnits)
          ..writeUint16(2)
          ..writeUint16(2)
          ..writeUint16List([0, 0, 255, 255])
          ..writeUint8(1)
          ..writeUint8(1)
          ..writeZeros(8)
          ..writeFloat32(16)
          ..writeUint32(1)
          ..writeUint32(0)
          ..writeFloat32(1)
          ..writeString('hdra')
          ..writeUint32(6)
          ..writeUint32(0)
          ..writeFloat32(20)
          ..writeFloat32(30)
          ..writeUint32(0)
          ..writeUint32(0)
          ..writeFloat32(1)
          ..writeZeros(6))
        .takeBytes();
