/// Reports malformed, truncated, or unsupported PSD input.
final class PsdFormatException implements FormatException {
  /// Human-readable explanation of the malformed PSD data.
  @override
  final String message;

  /// Input object associated with the failure, when available.
  @override
  final Object? source;

  /// Absolute byte offset associated with the failure, when available.
  @override
  final int? offset;

  /// Creates an error at an optional byte [offset].
  const PsdFormatException(this.message, [this.source, this.offset]);

  @override
  String toString() {
    final String location = offset == null ? '' : ' at byte $offset';
    return 'PsdFormatException$location: $message';
  }
}

/// Reports data that cannot be represented by the requested PSD version.
final class PsdWriteException implements Exception {
  /// Explains why encoding failed.
  final String message;

  /// Creates an error with a user-facing [message].
  const PsdWriteException(this.message);

  @override
  String toString() => 'PsdWriteException: $message';
}
