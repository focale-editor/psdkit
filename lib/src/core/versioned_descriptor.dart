import 'dart:typed_data';

import 'package:pscore/pscore.dart';

/// Decodes a version-16 descriptor, accepting only zero bytes after its body.
PsDescriptor decodePsdVersionedDescriptor(Uint8List bytes) {
  final ({PsVersionedDescriptor value, int bytesRead}) decoded = PsVersionedDescriptorCodec.decodePrefix(bytes, expectedVersion: 16);
  if (bytes.skip(decoded.bytesRead).any((byte) => byte != 0)) {
    throw PsFormatException(message: 'Unexpected bytes after versioned descriptor', source: bytes, offset: decoded.bytesRead);
  }
  return decoded.value.descriptor;
}

/// Encodes a version-16 descriptor with zero padding to a four-byte boundary.
Uint8List encodePsdVersionedDescriptor(PsDescriptor descriptor) {
  final PsBinaryWriter writer = PsBinaryWriter();
  PsVersionedDescriptorCodec.write(writer, PsVersionedDescriptor(descriptor: descriptor));
  writer.writeZeros((4 - writer.length % 4) % 4);
  return writer.takeBytes();
}
