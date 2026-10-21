part of '../smart_objects.dart';

/// One calendar timestamp stored by an external linked resource.
final class PsdLinkedResourceTimestamp {
  /// Four-digit year.
  final int year;

  /// Month from 1 through 12.
  final int month;

  /// Day of month.
  final int day;

  /// Hour from 0 through 23.
  final int hour;

  /// Minute from 0 through 59.
  final int minute;

  /// Seconds, including a possible fractional part.
  final double seconds;

  /// Creates an exact linked-resource timestamp.
  const PsdLinkedResourceTimestamp({
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    required this.seconds,
  });

  /// Converts the timestamp to UTC when all components are accepted by Dart.
  DateTime? get utcDateTime {
    if (month < 1 || month > 12 || day < 1 || day > 31 || hour < 0 || hour > 23 || minute < 0 || minute > 59 || seconds < 0) {
      return null;
    }
    final int wholeSeconds = seconds.floor();
    final int microseconds = ((seconds - wholeSeconds) * Duration.microsecondsPerSecond).round();
    return DateTime.utc(year, month, day, hour, minute, wholeSeconds, 0, microseconds);
  }
}

/// Base type for one length-prefixed entry in a linked-resource block.
sealed class PsdLinkedResourceEntry {
  /// Creates a linked-resource entry base value.
  const PsdLinkedResourceEntry();

  /// Exact alignment bytes following the length-prefixed entry body.
  Uint8List get entryPadding;
}

/// An embedded, external, or alias-linked Photoshop file resource.
final class PsdLinkedResource extends PsdLinkedResourceEntry {
  /// Stored entry type.
  final PsdLinkedResourceType type;

  /// Linked-resource structure version from 1 through 7.
  final int version;

  /// Pascal-string resource identifier used by smart-object layers.
  final String id;

  /// Exact padding that followed the Pascal identifier.
  final Uint8List idPadding;

  /// Original file name without a terminal NUL.
  final String name;

  /// Whether the stored Unicode name ended in NUL.
  final bool nameHasTerminalNull;

  /// Four-character original file type.
  final String fileType;

  /// Four-character original file creator.
  final String fileCreator;

  /// Optional file-open descriptor.
  final PsdVersionedDescriptor? fileOpenDescriptor;

  /// Stored content-data length, retained for non-embedded variants.
  final int declaredDataLength;

  /// External-file location and metadata descriptor.
  final PsdVersionedDescriptor? linkedFileDescriptor;

  /// External-file modification timestamp.
  final PsdLinkedResourceTimestamp? timestamp;

  /// External file size in bytes.
  final int? externalFileSize;

  /// Historical alias bytes.
  final Uint8List aliasData;

  /// Complete embedded file bytes for `liFD` entries.
  final Uint8List? data;

  /// Child document identifier introduced in version 5.
  final String? childDocumentId;

  /// Whether the stored child document identifier ended in NUL.
  final bool childDocumentIdHasTerminalNull;

  /// Library asset modification time introduced in version 6.
  final double? assetModificationTime;

  /// Library asset lock flag introduced in version 7.
  final bool? assetLocked;

  /// Uninterpreted bytes remaining inside the length-prefixed entry.
  final Uint8List trailingData;

  /// Exact alignment bytes following the entry body.
  @override
  final Uint8List entryPadding;

  /// Creates one linked Photoshop file resource.
  PsdLinkedResource({
    required this.type,
    this.version = 7,
    required this.id,
    Uint8List? idPadding,
    required this.name,
    this.nameHasTerminalNull = true,
    this.fileType = '    ',
    this.fileCreator = '    ',
    this.fileOpenDescriptor,
    int? declaredDataLength,
    this.linkedFileDescriptor,
    this.timestamp,
    this.externalFileSize,
    Uint8List? aliasData,
    this.data,
    this.childDocumentId,
    this.childDocumentIdHasTerminalNull = true,
    this.assetModificationTime,
    this.assetLocked,
    Uint8List? trailingData,
    Uint8List? entryPadding,
  }) : declaredDataLength = declaredDataLength ?? data?.length ?? 0,
       idPadding = idPadding ?? Uint8List(0),
       aliasData = aliasData ?? Uint8List(0),
       trailingData = trailingData ?? Uint8List(0),
       entryPadding = entryPadding ?? Uint8List(0);

  /// Returns a copy whose embedded file bytes are [bytes].
  PsdLinkedResource withData(Uint8List bytes) => PsdLinkedResource(
    type: PsdLinkedResourceType.embedded,
    version: version,
    id: id,
    idPadding: idPadding,
    name: name,
    nameHasTerminalNull: nameHasTerminalNull,
    fileType: fileType,
    fileCreator: fileCreator,
    fileOpenDescriptor: fileOpenDescriptor,
    declaredDataLength: bytes.length,
    linkedFileDescriptor: null,
    data: bytes,
    childDocumentId: childDocumentId,
    childDocumentIdHasTerminalNull: childDocumentIdHasTerminalNull,
    assetModificationTime: assetModificationTime,
    assetLocked: assetLocked,
    trailingData: trailingData,
  );
}

/// One opaque linked-resource entry retained with its exact body.
final class PsdRawLinkedResource extends PsdLinkedResourceEntry {
  /// Exact bytes following the outer 64-bit length.
  final Uint8List data;

  /// Exact alignment bytes following the entry body.
  @override
  final Uint8List entryPadding;

  /// Creates an opaque linked-resource entry.
  const PsdRawLinkedResource({required this.data, required this.entryPadding});
}

/// A complete `lnkD`, `lnk2`, or `lnk3` document block.
final class PsdLinkedResourceBlock {
  /// Four-character tagged-block key.
  final String blockKey;

  /// Length-prefixed entries in file order.
  final List<PsdLinkedResourceEntry> entries;

  /// Uninterpreted bytes after the final complete entry.
  final Uint8List trailingData;

  /// Creates a linked-resource block.
  PsdLinkedResourceBlock({this.blockKey = 'lnk2', required this.entries, Uint8List? trailingData}) : trailingData = trailingData ?? Uint8List(0) {
    if (!psdLinkedResourceKeys.contains(blockKey)) {
      throw ArgumentError.value(blockKey, 'blockKey', 'must be lnkD, lnk2, or lnk3');
    }
  }

  /// All semantically decoded linked resources.
  List<PsdLinkedResource> get resources => <PsdLinkedResource>[
    for (final PsdLinkedResourceEntry entry in entries)
      if (entry is PsdLinkedResource) entry,
  ];
}
