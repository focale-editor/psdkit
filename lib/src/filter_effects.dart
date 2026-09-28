import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:psdkit/src/compression.dart';
import 'package:psdkit/src/model.dart';

/// Document-level pixel-cache keys used by Photoshop smart filters.
const Set<String> psdFilterEffectsKeys = {'FEid', 'FXid'};

/// A compressed filter-cache plane, inflated only on explicit request.
///
/// Filter-cache PackBits row lengths are always 32-bit, even in a PSD. This
/// differs from ordinary PSD layer channels. Unknown compression codes remain
/// opaque and can be written back without attempting to interpret their pixels.
final class PsdFilterEffectChannel {
  /// Stored compression code, or null for a written but empty plane record.
  final int? compression;

  /// Compressed bytes, excluding the two-byte compression code.
  final Uint8List data;

  /// Wraps compressed data without inflating it.
  PsdFilterEffectChannel({required this.compression, required Uint8List data}) : data = data.asUnmodifiableView();

  /// Compresses one exact planar sample buffer using wide PackBits lengths.
  factory PsdFilterEffectChannel.fromPixels({
    required Uint8List pixels,
    required int width,
    required int height,
    int depth = 8,
    PsdCompression compression = PsdCompression.rle,
    int maxDecodedBytes = 64 * 1024 * 1024,
  }) {
    _validatePlane(width: width, height: height, depth: depth, maximumBytes: maxDecodedBytes);
    return PsdFilterEffectChannel(
      compression: compression.code,
      data: encodePsdChannel(compression: compression, data: pixels, width: width, height: height, depth: depth, wideRowLengths: true),
    );
  }

  /// Inflates exactly one bounded plane, rejecting unknown compression codes.
  Uint8List decodePixels({required int width, required int height, required int depth, int maxDecodedBytes = 64 * 1024 * 1024}) {
    _validatePlane(width: width, height: height, depth: depth, maximumBytes: maxDecodedBytes);
    final PsdCompression? method = PsdCompression.values.where((value) => value.code == compression).firstOrNull;
    if (method == null) {
      throw PsFormatException(message: 'Unsupported filter-effect compression: $compression');
    }
    return decodePsdChannel(compression: method, payload: data, width: width, height: height, depth: depth, wideRowLengths: true, maxDecodedBytes: maxDecodedBytes);
  }
}

/// The independently bounded, shared mask following a filter pixel cache.
final class PsdFilterEffectMask {
  /// Document-space bounds, independent of the cache's pixel rectangle.
  final PsdRectangle rectangle;

  /// Grayscale mask samples stored at the parent effect's depth.
  final PsdFilterEffectChannel channel;

  /// Creates a shared filter mask without conflating it with a layer mask.
  const PsdFilterEffectMask({required this.rectangle, required this.channel});
}

/// One instance's unfiltered projected cache and optional shared filter mask.
final class PsdFilterEffect {
  /// Placement identity matching the smart-object descriptor's `placed` key.
  ///
  /// This is not `Idnt`, which identifies the possibly shared source file.
  final String id;

  /// Effect record version, independent of the enclosing block version.
  final int version;

  /// Document-space bounds of the cached planes.
  final PsdRectangle rectangle;

  /// Bits per sample for cache and mask planes.
  final int depth;

  /// Indexed planes including the user-mask and sheet-alpha slots.
  ///
  /// Null denotes an unwritten slot; an empty written slot uses a channel with
  /// null compression. RGB fixtures use 26 slots and sheet alpha at index 25.
  final List<PsdFilterEffectChannel?> channels;

  /// Optional painted mask, separate from the indexed cache planes.
  final PsdFilterEffectMask? mask;

  /// Whether an optional mask-presence byte was present, even when zero.
  final bool maskRecordPresent;

  /// Uninterpreted extension following the indexed cache planes.
  final Uint8List bodyTrailingData;

  /// Uninterpreted extension following the optional mask record.
  final Uint8List trailingData;

  /// Creates one instance cache while preserving unsupported extensions.
  PsdFilterEffect({
    required this.id,
    this.version = 1,
    required this.rectangle,
    required this.depth,
    required List<PsdFilterEffectChannel?> channels,
    this.mask,
    bool maskRecordPresent = true,
    Uint8List? bodyTrailingData,
    Uint8List? trailingData,
  }) : channels = List.unmodifiable(channels),
       maskRecordPresent = maskRecordPresent || mask != null,
       bodyTrailingData = (bodyTrailingData ?? Uint8List(0)).asUnmodifiableView(),
       trailingData = (trailingData ?? Uint8List(0)).asUnmodifiableView();
}

/// Versioned collection of instance caches in an `FEid` or `FXid` block.
final class PsdFilterEffects {
  /// Container payload version, normally 3 in current Photoshop files.
  final int version;

  /// Ordered instance caches; identifiers are not assumed to be unique.
  final List<PsdFilterEffect> effects;

  /// Creates a block without decoding or copying its compressed planes.
  PsdFilterEffects({this.version = 3, required List<PsdFilterEffect> effects}) : effects = List.unmodifiable(effects);
}

/// Bounded framing for Photoshop filter caches, without eager pixel inflation.
abstract final class PsdFilterEffectsCodec {
  /// Parses a single tagged-block payload, not its `8BIM` framing.
  static PsdFilterEffects decode(Uint8List bytes, {int maxEffects = 4096, int maxEncodedBytes = 256 * 1024 * 1024}) {
    if (bytes.length > maxEncodedBytes || maxEffects < 0) {
      throw const PsFormatException(message: 'Filter-effect block exceeds configured limits');
    }
    final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
    final int version = reader.readUint32();
    if (version < 1 || version > 3) {
      throw PsFormatException(message: 'Unsupported filter-effects version $version');
    }
    final List<PsdFilterEffect> effects = [];
    while (!reader.isAtEnd) {
      if (effects.length >= maxEffects) {
        throw const PsFormatException(message: 'Too many filter-effect records');
      }
      final int length = reader.readLength(wide: true, label: 'filter effect');
      effects.add(_readEffect(reader.readReader(length)));
      for (int padding = (4 - length % 4) % 4; padding > 0; padding--) {
        if (reader.readUint8() != 0) {
          throw const PsFormatException(message: 'Nonzero filter-effect padding');
        }
      }
    }
    return PsdFilterEffects(version: version, effects: effects);
  }

  /// Writes a payload with the same 64-bit framing in PSD and PSB containers.
  static Uint8List encode(PsdFilterEffects value, {int maxEncodedBytes = 256 * 1024 * 1024}) {
    if (value.version < 1 || value.version > 3) {
      throw const PsWriteException(message: 'Unsupported filter-effects version');
    }
    // Admit all nested buffers before assembling any output or copying payloads.
    int length = 4;
    for (final PsdFilterEffect effect in value.effects) {
      _validateEffect(effect);
      int recordLength = 1 + effect.id.length + 4 + 8 + 24 + effect.bodyTrailingData.length + effect.trailingData.length;
      for (final PsdFilterEffectChannel? channel in effect.channels) {
        recordLength += 4 + (channel == null ? 0 : 8 + _channelLength(channel));
      }
      if (effect.maskRecordPresent) {
        recordLength += 1;
        if (effect.mask case final PsdFilterEffectMask mask) {
          recordLength += 16 + 8 + _channelLength(mask.channel);
        }
      }
      length += 8 + recordLength + (4 - recordLength % 4) % 4;
      if (length > maxEncodedBytes) {
        throw const PsWriteException(message: 'Filter-effect block exceeds configured limits');
      }
    }
    if (length > maxEncodedBytes) {
      throw const PsWriteException(message: 'Filter-effect block exceeds configured limits');
    }
    final PsBinaryWriter writer = PsBinaryWriter(initialCapacity: length)..writeUint32(value.version);
    for (final PsdFilterEffect effect in value.effects) {
      final PsBinaryWriter body = PsBinaryWriter();
      _writeRectangle(body, effect.rectangle);
      body
        ..writeUint32(effect.depth)
        ..writeUint32(effect.channels.length - 2);
      for (final PsdFilterEffectChannel? channel in effect.channels) {
        body.writeUint32(channel == null ? 0 : 1);
        if (channel != null) {
          _writeChannel(body, channel);
        }
      }
      body.writeBytes(effect.bodyTrailingData);
      final PsBinaryWriter record = PsBinaryWriter()
        ..writeUint8(effect.id.length)
        ..writeString(effect.id)
        ..writeUint32(effect.version)
        ..writeUint64(body.length)
        ..writeBytes(body.takeBytes());
      if (effect.maskRecordPresent) {
        record.writeUint8(effect.mask == null ? 0 : 1);
        if (effect.mask case final PsdFilterEffectMask mask) {
          _writeRectangle(record, mask.rectangle);
          _writeChannel(record, mask.channel);
        }
      }
      record.writeBytes(effect.trailingData);
      final int recordLength = record.length;
      writer
        ..writeUint64(recordLength)
        ..writeBytes(record.takeBytes())
        ..writeZeros((4 - recordLength % 4) % 4);
    }
    return writer.takeBytes();
  }

  /// Reads a bounded instance record and retains both extension areas.
  static PsdFilterEffect _readEffect(PsBinaryReader reader) {
    final String id = reader.readString(reader.readUint8());
    final int version = reader.readUint32();
    if (version > 1) {
      throw const PsFormatException(message: 'Unsupported filter-effect record version');
    }
    final PsBinaryReader body = reader.readReader(reader.readLength(wide: true, label: 'filter-effect body'));
    final PsdRectangle rectangle = _readRectangle(body);
    final int depth = body.readUint32();
    final int maximumChannels = body.readUint32();
    if (maximumChannels > 56) {
      throw const PsFormatException(message: 'Too many filter-effect channels');
    }
    final List<PsdFilterEffectChannel?> channels = [];
    for (int index = 0; index < maximumChannels + 2; index++) {
      channels.add(_readBoolean(body, byte: false) ? _readChannel(body) : null);
    }
    final bool maskRecordPresent = !reader.isAtEnd;
    final PsdFilterEffectMask? mask = maskRecordPresent && _readBoolean(reader, byte: true) ? PsdFilterEffectMask(rectangle: _readRectangle(reader), channel: _readChannel(reader)) : null;
    return PsdFilterEffect(
      id: id,
      version: version,
      rectangle: rectangle,
      depth: depth,
      channels: channels,
      mask: mask,
      maskRecordPresent: maskRecordPresent,
      bodyTrailingData: body.readView(body.remaining),
      trailingData: reader.readView(reader.remaining),
    );
  }

  /// Reads a strict presence flag without accepting unknown record layouts.
  static bool _readBoolean(PsBinaryReader reader, {required bool byte}) {
    final int value = byte ? reader.readUint8() : reader.readUint32();
    if (value > 1) {
      throw const PsFormatException(message: 'Invalid filter-effect presence flag');
    }
    return value == 1;
  }

  /// Reads a length-delimited compressed plane, including empty written slots.
  static PsdFilterEffectChannel _readChannel(PsBinaryReader reader) {
    final PsBinaryReader channel = reader.readReader(reader.readLength(wide: true, label: 'filter-effect channel'));
    final int? compression = channel.isAtEnd ? null : channel.readUint16();
    return PsdFilterEffectChannel(compression: compression, data: channel.readView(channel.remaining));
  }

  /// Counts a channel payload and validates values before output allocation.
  static int _channelLength(PsdFilterEffectChannel channel) {
    if (channel.compression == null && channel.data.isNotEmpty || channel.compression != null && (channel.compression! < 0 || channel.compression! > 65535)) {
      throw const PsWriteException(message: 'Invalid filter-effect compression marker');
    }
    return channel.compression == null ? 0 : 2 + channel.data.length;
  }

  /// Writes a compressed plane including its 64-bit length and method marker.
  static void _writeChannel(PsBinaryWriter writer, PsdFilterEffectChannel channel) {
    writer.writeUint64(_channelLength(channel));
    if (channel.compression case final int compression) {
      writer.writeUint16(compression);
    }
    writer.writeBytes(channel.data);
  }

  /// Reads the four signed document-space coordinates of a cache or mask.
  static PsdRectangle _readRectangle(PsBinaryReader reader) => PsdRectangle(top: reader.readInt32(), left: reader.readInt32(), bottom: reader.readInt32(), right: reader.readInt32());

  /// Writes a validated rectangle without changing its coordinate origin.
  static void _writeRectangle(PsBinaryWriter writer, PsdRectangle rectangle) {
    writer
      ..writeInt32(rectangle.top)
      ..writeInt32(rectangle.left)
      ..writeInt32(rectangle.bottom)
      ..writeInt32(rectangle.right);
  }

  /// Rejects truncated identifiers and out-of-range scalar fields on export.
  static void _validateEffect(PsdFilterEffect effect) {
    if (effect.id.length > 255 ||
        effect.id.codeUnits.any((value) => value > 255) ||
        effect.version < 0 ||
        effect.version > 1 ||
        effect.channels.length < 2 ||
        effect.channels.length > 58 ||
        effect.depth < 0 ||
        effect.depth > 0xffffffff) {
      throw const PsWriteException(message: 'Invalid filter-effect metadata');
    }
    if (!effect.maskRecordPresent && effect.trailingData.isNotEmpty) {
      throw const PsWriteException(message: 'Filter-effect extensions require a mask-presence byte');
    }
    for (final PsdRectangle rectangle in [effect.rectangle, ?effect.mask?.rectangle]) {
      if ([rectangle.top, rectangle.left, rectangle.bottom, rectangle.right].any((value) => value < -2147483648 || value > 2147483647)) {
        throw const PsWriteException(message: 'Filter-effect bounds exceed signed 32-bit coordinates');
      }
    }
  }
}

/// Checks pixel geometry before any inflate, encode, or predictor allocation.
void _validatePlane({required int width, required int height, required int depth, required int maximumBytes}) {
  if (width < 1 || height < 1 || width > 300000 || height > 300000 || !const [1, 8, 16, 32].contains(depth) || psdRowBytes(width, depth) * height > maximumBytes) {
    throw const PsFormatException(message: 'Filter-effect plane exceeds supported geometry or memory limits');
  }
}
