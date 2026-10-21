part of '../image_resources.dart';

/// Writes one semantic resource model.
void _writeImageResource(PsBinaryWriter writer, PsdImageResourceData value) {
  switch (value) {
    case PsdRawImageResource():
      writer.writeBytes(value.data);
    case PsdBinaryMetadataResource():
      writer.writeBytes(value.data);
    case PsdByteImageResource():
      _requireUnsigned(value.value, 8, 'image-resource byte');
      writer.writeUint8(value.value);
    case PsdShortImageResource():
      _requireUnsigned(value.value, 16, 'image-resource short');
      writer.writeUint16(value.value);
    case PsdIntegerImageResource():
      writer.writeInt32(value.value);
    case PsdByteListImageResource():
      for (final int item in value.values) {
        _requireUnsigned(item, 8, 'image-resource byte-list item');
        writer.writeUint8(item);
      }
    case PsdIntegerListImageResource():
      _writeIntegerList(writer, value);
    case PsdStringListImageResource():
      for (final String item in value.values) {
        if (value.unicode) {
          _writeUnicodeString(writer, item);
        } else {
          _writePascalString(writer, item);
        }
      }
    case PsdTextImageResource():
      if (value.utf8) {
        final Uint8List? sourceData = value._sourceData;
        if (sourceData != null && value.value == value._sourceValue) {
          writer.writeBytes(sourceData);
        } else {
          writer.writeBytes(utf8.encode(value.value));
        }
      } else {
        _writeUnicodeString(writer, value.value);
      }
    case PsdResolutionInfo():
      writer
        ..writeUint32(value.horizontalFixed)
        ..writeUint16(value.horizontalResolutionUnit)
        ..writeUint16(value.widthUnit)
        ..writeUint32(value.verticalFixed)
        ..writeUint16(value.verticalResolutionUnit)
        ..writeUint16(value.heightUnit);
    case PsdImageResourceColor():
      if (value.components.length != 4) {
        throw const PsWriteException(message: 'Image-resource colors require four components');
      }
      writer.writeUint16(value.colorSpace);
      value.components.forEach(writer.writeUint16);
    case PsdPrintFlags():
      final List<bool> flags = <bool>[value.labels, value.cropMarks, value.colorBars, value.registrationMarks, value.negative, value.flip, value.interpolate, value.caption];
      if (value.printFlags case final bool flag) {
        flags.add(flag);
      }
      for (final bool flag in flags) {
        writer.writeUint8(flag ? 1 : 0);
      }
    case PsdGridAndGuides():
      writer
        ..writeUint32(value.version)
        ..writeUint32(value.horizontalCycle)
        ..writeUint32(value.verticalCycle)
        ..writeUint32(value.guides.length);
      for (final PsdGuide guide in value.guides) {
        writer
          ..writeUint32(guide.location)
          ..writeUint8(guide.direction);
      }
    case PsdHalftoneScreens():
      for (final PsdHalftoneScreen screen in value.screens) {
        writer
          ..writeUint32((screen.frequency * 65536).round())
          ..writeUint16(screen.unit)
          ..writeInt32((screen.angle * 65536).round())
          ..writeUint16(screen.shape)
          ..writeZeros(4)
          ..writeUint8(screen.useAccurate ? 1 : 0)
          ..writeUint8(screen.usePrinter ? 1 : 0);
      }
    case PsdTransferFunctions():
      for (final PsdTransferFunction function in value.functions) {
        if (function.curve.length != 13) {
          throw const PsWriteException(message: 'Transfer functions require thirteen curve values');
        }
        function.curve.forEach(writer.writeInt16);
        writer.writeUint16(function.override);
      }
    case PsdThumbnailResource():
      writer
        ..writeUint32(value.format)
        ..writeUint32(value.width)
        ..writeUint32(value.height)
        ..writeUint32(value.rowBytes)
        ..writeUint32(value.totalSize)
        ..writeUint32(value.data.length)
        ..writeUint16(value.bitsPerPixel)
        ..writeUint16(value.planes)
        ..writeBytes(value.data);
    case PsdIccProfileResource():
      writer.writeBytes(value.data);
    case PsdPixelAspectRatio():
      writer
        ..writeUint32(value.version)
        ..writeFloat64(value.ratio);
    case PsdPrintScale():
      writer
        ..writeUint16(value.style)
        ..writeFloat32(value.x)
        ..writeFloat32(value.y)
        ..writeFloat32(value.scale);
    case PsdPrintFlagsInfo():
      writer
        ..writeUint16(value.version)
        ..writeUint8(value.centerCropMarks ? 1 : 0)
        ..writeUint8(value.reserved)
        ..writeUint32(value.bleedWidth)
        ..writeUint16(value.bleedScale);
    case PsdVersionInfo():
      writer
        ..writeUint32(value.version)
        ..writeUint8(value.hasRealMergedData ? 1 : 0);
      _writeUnicodeString(writer, value.writerName);
      _writeUnicodeString(writer, value.readerName);
      writer.writeUint32(value.fileVersion);
    case PsdUrlList():
      writer.writeUint32(value.items.length);
      for (final PsdUrlItem item in value.items) {
        writer
          ..writeUint32(item.number)
          ..writeUint32(item.id);
        _writeUnicodeString(writer, item.name);
      }
    case PsdDescriptorImageResource():
      writer
        ..writeUint32(value.descriptorVersion)
        ..writeBytes(PsDescriptorCodec.encode(value.descriptor))
        ..writeBytes(value.trailingData);
    case PsdDisplayInfo():
      writer.writeUint32(value.version);
      for (final PsdAlphaChannelDisplay channel in value.channels) {
        if (channel.components.length != 4) {
          throw const PsWriteException(message: 'Alpha-channel display records require four color components');
        }
        writer.writeUint16(channel.colorSpace);
        channel.components.forEach(writer.writeUint16);
        writer
          ..writeUint16(channel.opacity)
          ..writeUint8(channel.mode);
      }
    case PsdPathImageResource():
      writer.writeBytes(PsdVectorPathCodec.encode(value.path));
    case PsdSlicesResource():
      writer
        ..writeUint32(value.version)
        ..writeUint32(value.descriptorVersion)
        ..writeBytes(PsDescriptorCodec.encode(value.descriptor))
        ..writeBytes(value.trailingData);
  }
}

/// Writes a counted or uncounted fixed-width integer list.
void _writeIntegerList(PsBinaryWriter writer, PsdIntegerListImageResource value) {
  switch (value.layout) {
    case PsdImageResourceListLayout.uncounted:
      break;
    case PsdImageResourceListLayout.uint16Count:
      _requireUnsigned(value.values.length, 16, 'image-resource list count');
      writer.writeUint16(value.values.length);
    case PsdImageResourceListLayout.uint32Count:
      writer.writeUint32(value.values.length);
  }
  for (final int item in value.values) {
    if (value.valueBytes == 2) {
      _requireUnsigned(item, 16, 'image-resource list item');
      writer.writeUint16(item);
    } else if (value.valueBytes == 4) {
      _requireUnsigned(item, 32, 'image-resource list item');
      writer.writeUint32(item);
    } else {
      throw const PsWriteException(message: 'Image-resource integer lists require two-byte or four-byte values');
    }
  }
}
