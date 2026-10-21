part of '../codec.dart';

/// Endian conversion for Photoshop's legacy effects, adjustments and pixel caches.
extension _PsdTiffPayloads on _PsdTiffTranscoder {
  /// Converts legacy layer-effects envelopes and fixed numeric fields.
  void legacyEffects() {
    scalar(2);
    final int count = number(2);
    if (count > remaining ~/ 12) {
      throw const PsFormatException(message: 'Invalid legacy effect count');
    }
    for (int i = 0; i < count; i++) {
      key();
      final String name = key();
      sized(() {
        switch (name) {
          case 'cmnS':
            scalar(4);
            raw(1);
            scalar(2);
          case 'dsdw' || 'isdw':
            scalars(4, 5);
            scalars(2, 5);
            key();
            key();
            raw(3);
            if (remaining >= 10) {
              scalars(2, 5);
            }
          case 'oglw' || 'iglw':
            scalars(4, 3);
            scalars(2, 5);
            key();
            key();
            raw(2);
            if (name == 'iglw' && remaining >= 11) {
              raw(1);
            }
            if (remaining >= 10) {
              scalars(2, 5);
            }
          case 'bevl':
            scalars(4, 4);
            key();
            key();
            key();
            key();
            scalars(2, 10);
            raw(6);
            if (remaining >= 20) {
              scalars(2, 10);
            }
          case 'sofi':
            scalar(4);
            key();
            key();
            scalars(2, 5);
            raw(2);
            if (remaining >= 10) {
              scalars(2, 5);
            }
          default:
            throw PsFormatException(message: 'Unknown legacy effect $name');
        }
      });
    }
  }

  /// Converts smart-filter cache sections, including their wide RLE row tables.
  void filterEffects() {
    scalar(4);
    while (remaining >= 8) {
      final int length = number(8);
      region(length, () {
        while (remaining > 0) {
          pascal(1);
          scalar(4);
          sized(() {
            final int top = signed(4);
            scalar(4);
            final int bottom = signed(4);
            scalar(4);
            scalar(4);
            final int count = number(4);
            if (count > 56) {
              throw const PsFormatException(message: 'Too many filter-effect channels');
            }
            for (int i = 0; i < count + 2; i++) {
              if (number(4) != 0) {
                _effectPlane((bottom - top).clamp(0, 0x7fffffff));
              }
            }
          }, wide: true);
          if (remaining > 0 && number(1) != 0) {
            final int top = signed(4);
            scalar(4);
            final int bottom = signed(4);
            scalar(4);
            _effectPlane((bottom - top).clamp(0, 0x7fffffff));
          }
        }
      });
      raw(((4 - length % 4) % 4).clamp(0, remaining));
    }
    if (remaining > 3 || source.sublist(_offset, _end).any((byte) => byte != 0)) {
      throw const PsFormatException(message: 'Unexpected filter-effect trailing bytes');
    }
  }

  /// Converts one cached plane without changing its encoded pixel stream.
  void _effectPlane(int rows) => sized(() {
    if (number(2) == 1) {
      scalars(4, rows);
    }
  }, wide: true);

  /// Converts curve point arrays and their optional per-channel extension.
  void curves() {
    raw(1);
    scalar(2);
    final int bits = number(4);
    for (int bit = 0; bit < 32; bit++) {
      if ((bits & (1 << bit)) != 0) {
        scalars(2, number(2) * 2);
      }
    }
    if (remaining >= 10) {
      key();
      scalar(2);
      final int count = number(4);
      if (count > remaining ~/ 4) {
        throw const PsFormatException(message: 'Invalid curve extension count');
      }
      for (int i = 0; i < count; i++) {
        scalar(2);
        scalars(2, number(2) * 2);
      }
    }
  }

  /// Converts gradient-map stops and the mixed-width noise-gradient trailer.
  void gradientMap() {
    final int version = number(2);
    raw(2);
    if (version == 3) {
      key();
    }
    unicode();
    final int count = number(2);
    if (count > remaining ~/ 20) {
      throw const PsFormatException(message: 'Invalid gradient color-stop count');
    }
    for (int i = 0; i < count; i++) {
      scalars(4, 2);
      scalars(2, 6);
    }
    final int transparency = number(2);
    if (transparency > remaining ~/ 10) {
      throw const PsFormatException(message: 'Invalid gradient transparency-stop count');
    }
    for (int i = 0; i < transparency; i++) {
      scalars(4, 2);
      scalar(2);
    }
    scalars(2, (remaining ~/ 2).clamp(0, 4));
    if (remaining >= 4) {
      scalar(4);
    }
    scalars(2, remaining ~/ 2);
  }

  /// Converts pattern envelopes and virtual-memory channel headers.
  void patterns() {
    while (remaining >= 4) {
      final int length = number(4);
      if (length == 0) {
        continue;
      }
      region(length, () {
        scalar(4);
        final int mode = number(4);
        scalars(2, 2);
        unicode();
        pascal(1);
        if (mode == 2) {
          raw(768);
          _require(4);
          if (ByteData.sublistView(source).getUint32(_offset, from) != 3) {
            raw(4);
          }
        }
        scalar(4);
        sized(() {
          scalars(4, 4);
          final int count = number(4);
          if (count > 56) {
            throw const PsFormatException(message: 'Too many pattern channels');
          }
          for (int i = 0; i < count + 2 && remaining >= 4; i++) {
            if (number(4) == 0) {
              continue;
            }
            sized(() {
              if (remaining == 0) {
                return;
              }
              scalar(4);
              final int top = signed(4);
              scalar(4);
              final int bottom = signed(4);
              scalar(4);
              scalar(2);
              if (number(1) == 1) {
                scalars(2, (bottom - top).clamp(0, 0x7fffffff));
              }
            });
          }
        });
      });
      raw(((4 - length % 4) % 4).clamp(0, remaining));
    }
  }
}
