part of '../codec.dart';

/// Converts known Photoshop TIFF fields without touching compressed pixel samples.
///
/// All operations preserve lengths. Unknown Intel-order blocks carry a foreign
/// signature in the PSD model and can only be saved back to Intel-order TIFF.
final class _PsdTiffTranscoder {
  /// Original encoded bytes.
  final Uint8List source;

  /// Independent output buffer, modified only at typed scalar positions.
  final Uint8List output;

  /// Byte order of source structures.
  final Endian from;

  /// Byte order requested by the caller.
  final Endian to;

  /// Container version controlling wide lengths and RLE row counts.
  final PsdVersion version;

  /// Cursor and bounded end of the active region.
  int _offset = 0;
  int _end;

  /// Nesting depth shared by descriptors and blocks.
  int _depth = 0;

  /// Creates an isolated conversion with bounded nested regions.
  _PsdTiffTranscoder({required this.source, required this.from, required this.to, required this.version}) : output = Uint8List.fromList(source), _end = source.length;

  /// Bytes left in the active structure.
  int get remaining => _end - _offset;

  /// Validates a span before reading or reversing it.
  void _require(int length) {
    if (length < 0 || length > remaining) {
      throw PsFormatException(message: 'Truncated Photoshop TIFF structure', offset: _offset);
    }
  }

  /// Advances over opaque bytes.
  void raw(int length) {
    _require(length);
    _offset += length;
  }

  /// Reverses a scalar only when the target uses a different order.
  void scalar(int size) {
    _require(size);
    if (from != to) {
      for (int i = 0; i < size; i++) {
        output[_offset + i] = source[_offset + size - 1 - i];
      }
    }
    _offset += size;
  }

  /// Reads an unsigned scalar and converts its stored representation.
  int number(int size) {
    _require(size);
    final ByteData data = ByteData.sublistView(source);
    final int value;
    if (size == 8) {
      final int high = data.getUint32(_offset + (from == Endian.big ? 0 : 4), from);
      final int low = data.getUint32(_offset + (from == Endian.big ? 4 : 0), from);
      if (high > 0x1fffff) {
        throw const PsFormatException(message: 'TIFF length exceeds the portable integer range');
      }
      value = high * 4294967296 + low;
    } else {
      value = switch (size) {
        1 => data.getUint8(_offset),
        2 => data.getUint16(_offset, from),
        4 => data.getUint32(_offset, from),
        _ => throw StateError('Invalid scalar width'),
      };
    }
    scalar(size);
    return value;
  }

  /// Reads a signed rectangle coordinate or layer/channel count.
  int signed(int size) {
    final int value = number(size);
    final int sign = size == 2 ? 0x8000 : 0x80000000;
    return value >= sign ? value - sign * 2 : value;
  }

  /// Reads a canonical four-character key and reverses its stored spelling.
  String key() {
    _require(4);
    final String value = String.fromCharCodes(from == Endian.little ? source.sublist(_offset, _offset + 4).reversed : source.sublist(_offset, _offset + 4));
    scalar(4);
    return value;
  }

  /// Walks a fixed-width scalar array after validating its entire extent.
  void scalars(int size, int count) {
    if (count < 0 || count > remaining ~/ size) {
      throw const PsFormatException(message: 'Invalid Photoshop TIFF array count');
    }
    for (int i = 0; i < count; i++) {
      scalar(size);
    }
  }

  /// Converts a length-prefixed Unicode string.
  void unicode() => scalars(2, number(4));

  /// Copies a padded one-byte string.
  void pascal(int alignment) {
    final int length = number(1);
    raw(length);
    raw((alignment - (length + 1) % alignment) % alignment);
  }

  /// Runs a child walker inside a declared byte span, copying its opaque suffix.
  void region(int length, void Function() walk) {
    _require(length);
    if (++_depth > 64) {
      throw const PsFormatException(message: 'Photoshop TIFF nesting exceeds 64');
    }
    final int end = _end;
    _end = _offset + length;
    try {
      walk();
      _offset = _end;
    } finally {
      _end = end;
      _depth--;
    }
  }

  /// Reads a length and bounds its nested payload.
  void sized(void Function() walk, {bool wide = false}) => region(number(wide ? 8 : 4), walk);

  /// Whether a block starts at the given source position.
  bool _signatureAt(int offset) => offset + 4 <= _end && const {'8BIM', '8B64', 'MIB8', '46B8'}.contains(String.fromCharCodes(source.sublist(offset, offset + 4)));

  /// Converts a sequence of layer or document tagged blocks.
  void blocks() {
    while (remaining >= 12 && _signatureAt(_offset)) {
      final int signatureOffset = _offset;
      final String storedSignature = String.fromCharCodes(source.sublist(_offset, _offset + 4));
      final bool foreign = from == Endian.big && const {'MIB8', '46B8'}.contains(storedSignature);
      final String signature = foreign ? storedSignature : key();
      if (foreign) {
        raw(4);
      }
      final String name = key();
      final bool wide = version == PsdVersion.psb && _widePsbTaggedBlocks.contains(name);
      final int length = number(wide ? 8 : 4);
      if (foreign) {
        if (to != Endian.little) {
          throw PsWriteException(message: 'Cannot convert opaque Intel-order $name data to PSD byte order');
        }
        raw(length);
      } else {
        bool handled = true;
        region(length, () {
          handled = length == 0 || blockBody(name);
        });
        if (!handled && from != to) {
          if (from == Endian.little) {
            output.setRange(signatureOffset, signatureOffset + 4, (signature == '8B64' ? '46B8' : 'MIB8').codeUnits);
          } else {
            throw PsWriteException(message: 'Cannot convert opaque $name data to Intel TIFF byte order');
          }
        }
      }
      int padding = 0;
      while (padding < 4 && _offset + padding < _end && !_signatureAt(_offset + padding)) {
        padding++;
      }
      if (padding < 4) {
        raw(padding);
      } else if (remaining <= 3) {
        raw(remaining);
      } else {
        break;
      }
    }
  }

  /// Converts layouts whose endian-sensitive fields are established by evidence.
  bool blockBody(String name) {
    switch (name) {
      case 'Layr' || 'Lr16' || 'Lr32':
        layerInfo();
      case 'luni':
        unicode();
      case 'lsct' || 'lsdk':
        scalar(4);
        if (remaining >= 8) {
          key();
          key();
        }
        if (remaining >= 4) {
          scalar(4);
        }
      case 'lyid' || 'lspf' || 'lyvr' || 'sn2P' || 'vowv':
        scalar(4);
      case 'Txt2' || 'clbl' || 'infx' || 'knko' || 'tsly' || 'lmgm' || 'vmgm' || 'iOpa' || 'nvrt':
        raw(remaining);
      case 'lnsr':
        key();
      case 'lclr' || 'LMsk':
        scalars(2, (remaining ~/ 2).clamp(0, name == 'LMsk' ? 6 : 4));
      case 'FMsk' || 'mixr' || 'selc':
        scalars(2, remaining ~/ 2);
      case 'fxrp':
        scalars(8, remaining ~/ 8);
      case 'brst':
        scalars(4, remaining ~/ 4);
      case 'lfx2' || 'lmfx' || 'lfxs' || 'CAI ' || 'vogk':
        scalar(4);
        versionedDescriptor();
      case 'SoCo' || 'GdFl' || 'PtFl' || 'vstk' || 'blwh' || 'vibA' || 'CgEd' || 'artb' || 'artd' || 'cinf' || 'cust' || 'PxSD' || 'GenI' || 'OCIO' || 'extn' || 'pths':
        versionedDescriptor();
      case 'clrL':
        scalar(2);
        versionedDescriptor();
      case 'vscg':
        key();
        versionedDescriptor();
      case 'SoLd' || 'SoLE':
        key();
        scalar(4);
        versionedDescriptor();
      case 'PlLd':
        key();
        scalar(4);
        pascal(1);
        scalars(4, 4);
        scalars(8, 8);
        scalar(4);
        versionedDescriptor();
      case 'TySh':
        scalar(2);
        scalars(8, 6);
        scalar(2);
        versionedDescriptor();
        scalar(2);
        versionedDescriptor();
        scalars(4, 4);
      case 'vmsk' || 'vsms':
        scalars(4, 2);
        paths();
      case 'levl':
        scalar(2);
        scalars(2, (remaining ~/ 2).clamp(0, 29 * 5));
        if (remaining >= 4) {
          key();
        }
        scalars(2, remaining ~/ 2);
      case 'hue2':
        scalar(2);
        raw(2);
        scalars(2, remaining ~/ 2);
      case 'brit':
        scalars(2, (remaining ~/ 2).clamp(0, 3));
      case 'thrs' || 'post':
        scalar(2);
      case 'expA':
        scalar(2);
        scalars(4, 3);
      case 'blnc':
        scalars(2, (remaining ~/ 2).clamp(0, 9));
      case 'phfl':
        final int version = number(2);
        if (version == 2) {
          scalars(2, 5);
          scalar(4);
        } else if (version == 3) {
          scalars(4, 4);
        } else {
          throw const PsFormatException(message: 'Unsupported photo-filter version');
        }
        raw(1);
      case 'lrFX':
        legacyEffects();
      case 'FEid' || 'FXid':
        filterEffects();
      case 'curv':
        curves();
      case 'grdm':
        gradientMap();
      case 'Patt' || 'Pat2' || 'Pat3':
        patterns();
      case 'shmd':
        metadata();
      case 'lnk2' || 'lnk3' || 'lnkD' || 'lnkE':
        linked();
      default:
        return false;
    }
    return true;
  }

  /// Converts layer records and the compression headers of each channel.
  void layerInfo() {
    final int count = signed(2).abs();
    if (count > remaining ~/ 34) {
      throw const PsFormatException(message: 'Invalid TIFF layer count');
    }
    final List<({List<(int, int)> channels, List<int> heights})> records = [];
    for (int i = 0; i < count; i++) {
      final int top = signed(4);
      scalar(4);
      final int bottom = signed(4);
      scalar(4);
      final int count = number(2);
      if (count > 56) {
        throw const PsFormatException(message: 'Too many TIFF layer channels');
      }
      final List<(int, int)> channels = [for (int c = 0; c < count; c++) (signed(2), number(version == PsdVersion.psb ? 8 : 4))];
      if (key() != '8BIM') {
        throw const PsFormatException(message: 'Invalid TIFF layer blend signature');
      }
      key();
      raw(4);
      final List<int> heights = [(bottom - top).clamp(0, 0x7fffffff), 0, 0];
      sized(() {
        sized(() {
          final (int, int) masks = mask(hasRealMask: channels.any((channel) => channel.$1 == -3));
          heights[1] = masks.$1;
          heights[2] = masks.$2;
        });
        sized(() => raw(remaining)); // Blend ranges are byte values in either order.
        pascal(4);
        blocks();
      });
      records.add((channels: channels, heights: heights));
    }
    for (final record in records) {
      for (final (int id, int length) in record.channels) {
        if (length == 0) {
          continue;
        }
        region(length, () {
          final int compression = number(2);
          if (compression == 1) {
            scalars(
              version == PsdVersion.psb ? 4 : 2,
              record.heights[id == -2
                  ? 1
                  : id == -3
                  ? 2
                  : 0],
            );
          }
          raw(remaining);
        });
      }
    }
  }

  /// Converts raster-mask geometry and optional density/feather parameters.
  (int, int) mask({required bool hasRealMask}) {
    if (remaining == 0) {
      return (0, 0);
    }
    final int top = signed(4);
    scalar(4);
    final int bottom = signed(4);
    scalar(4);
    raw(1);
    final int flags = number(1);
    int realHeight = 0;
    if (hasRealMask) {
      raw(2);
      final int realTop = signed(4);
      scalar(4);
      final int realBottom = signed(4);
      scalar(4);
      realHeight = (realBottom - realTop).clamp(0, 0x7fffffff);
    }
    if ((flags & 16) != 0 && remaining > 2) {
      final int parameters = number(1);
      if ((parameters & 1) != 0) {
        raw(1);
      }
      if ((parameters & 2) != 0) {
        scalar(8);
      }
      if ((parameters & 4) != 0) {
        raw(1);
      }
      if ((parameters & 8) != 0) {
        scalar(8);
      }
    }
    return ((bottom - top).clamp(0, 0x7fffffff), realHeight);
  }

  /// Converts a descriptor version followed by its recursive object.
  void versionedDescriptor() {
    if (number(4) != 16) {
      throw const PsFormatException(message: 'Unsupported TIFF descriptor version');
    }
    descriptor();
  }

  /// Converts an Action Descriptor while leaving raw data values untouched.
  void descriptor() {
    if (++_depth > 64) {
      throw const PsFormatException(message: 'Descriptor nesting exceeds 64');
    }
    unicode();
    identifier();
    final int count = number(4);
    if (count > remaining ~/ 8) {
      throw const PsFormatException(message: 'Invalid TIFF descriptor count');
    }
    for (int i = 0; i < count; i++) {
      identifier();
      value();
    }
    _depth--;
  }

  /// Converts an Adobe identifier; long names remain ASCII byte sequences.
  void identifier() {
    final int length = number(4);
    if (length == 0) {
      key();
    } else {
      raw(length);
    }
  }

  /// Converts a named class.
  void namedClass() {
    unicode();
    identifier();
  }

  /// Converts one typed descriptor value with bounded list recursion.
  void value() {
    if (++_depth > 64) {
      throw const PsFormatException(message: 'Descriptor nesting exceeds 64');
    }
    switch (key()) {
      case 'Objc' || 'GlbO':
        descriptor();
      case 'VlLs':
        final int count = number(4);
        if (count > remaining ~/ 4) {
          throw const PsFormatException(message: 'Invalid descriptor list');
        }
        for (int i = 0; i < count; i++) {
          value();
        }
      case 'obj ':
        final int count = number(4);
        if (count > remaining ~/ 4) {
          throw const PsFormatException(message: 'Invalid reference count');
        }
        for (int i = 0; i < count; i++) {
          reference();
        }
      case 'doub' || 'comp':
        scalar(8);
      case 'UntF':
        key();
        scalar(8);
      case 'UnFl':
        key();
        scalars(8, number(4));
      case 'TEXT':
        unicode();
      case 'enum':
        identifier();
        identifier();
      case 'long':
        scalar(4);
      case 'bool':
        raw(1);
      case 'type' || 'GlbC':
        namedClass();
      case 'alis' || 'Pth ' || 'tdta':
        raw(number(4));
      case 'ObAr':
        scalar(4);
        descriptor();
      case 'Idnt' || 'indx':
        scalar(4);
      case 'prop':
        namedClass();
        identifier();
      case 'Clss':
        namedClass();
      case 'Enmr':
        namedClass();
        identifier();
        identifier();
      case 'rele':
        namedClass();
        scalar(4);
      case 'name':
        namedClass();
        unicode();
      default:
        throw const PsFormatException(message: 'Unknown TIFF descriptor value type');
    }
    _depth--;
  }

  /// Converts descriptor references, whose class precedes the selected value.
  void reference() {
    final String type = key();
    if (type == 'Idnt' || type == 'indx') {
      scalar(4);
      return;
    }
    namedClass();
    switch (type) {
      case 'prop':
        identifier();
      case 'Clss':
        break;
      case 'Enmr':
        identifier();
        identifier();
      case 'rele' || 'Idnt' || 'indx':
        scalar(4);
      case 'name':
        unicode();
      default:
        throw const PsFormatException(message: 'Unknown TIFF descriptor reference');
    }
  }

  /// Converts fixed-size vector path records.
  void paths() {
    while (remaining >= 26) {
      switch (number(2)) {
        case 1 || 2 || 4 || 5:
          scalars(4, 6);
        case 0 || 3:
          scalars(2, 12);
        case 7:
          scalars(4, 5);
          raw(4);
        case 8:
          scalar(2);
          raw(22);
        default:
          raw(24);
      }
    }
  }

  /// Converts metadata descriptors without dropping unknown subrecords.
  void metadata() {
    final int count = number(4);
    if (count > remaining ~/ 16) {
      throw const PsFormatException(message: 'Invalid layer metadata count');
    }
    for (int i = 0; i < count; i++) {
      key();
      final String name = key();
      raw(4);
      sized(() {
        if (name == 'mdyn') {
          scalars(4, remaining ~/ 4);
        } else if (const {'cmls', 'mlst', 'cust', 'tmln', 'sgrp', 'cinf'}.contains(name)) {
          versionedDescriptor();
        } else if (from != to) {
          throw PsFormatException(message: 'Unknown endian-sensitive metadata $name');
        }
      });
    }
  }

  /// Converts linked-object envelopes, retaining embedded file bytes unchanged.
  void linked() {
    while (remaining >= 8) {
      final int length = number(8);
      region(length, () {
        final String kind = key();
        final int version = number(4);
        pascal(1);
        unicode();
        key();
        key();
        final int size = number(8);
        if (number(1) != 0) {
          versionedDescriptor();
        }
        if (kind == 'liFE' && version > 3) {
          scalar(4);
          raw(4);
          scalar(8);
        }
        if (kind == 'liFE') {
          scalar(8);
        }
        if (kind == 'liFA') {
          raw(8);
        }
        if (kind == 'liFD') {
          raw(size);
        }
        if (version >= 5) {
          unicode();
        }
        if (version >= 6) {
          scalar(8);
        }
        if (version >= 7) {
          raw(1);
        }
        if (kind == 'liFE' && version == 2) {
          raw(size);
        }
      });
      raw(((4 - length % 4) % 4).clamp(0, remaining));
    }
  }

  /// Converts image resource envelopes and established numeric resource payloads.
  void resources() {
    while (remaining >= 12 && _signatureAt(_offset)) {
      key();
      final int id = number(2);
      pascal(2);
      final int length = number(4);
      region(length, () {
        switch (id) {
          case 1005:
            scalar(4);
            scalars(2, 2);
            scalar(4);
            scalars(2, 2);
          case 1024 || 1026:
            scalars(2, remaining ~/ 2);
          case 1037 || 1049:
            scalar(4);
          case 1069:
            scalar(2);
            scalars(4, remaining ~/ 4);
          case 1057:
            scalar(4);
            raw(1);
            unicode();
            unicode();
            scalar(4);
          case 1032:
            scalars(4, 3);
            final int count = number(4);
            if (count > remaining ~/ 5) {
              throw const PsFormatException(message: 'Invalid guide count');
            }
            for (int i = 0; i < count; i++) {
              scalar(4);
              raw(1);
            }
          case >= 2000 && <= 2997 || 2999:
            paths();
          default:
            raw(remaining);
        }
      });
      if (length.isOdd) {
        raw(1);
      }
    }
  }
}
