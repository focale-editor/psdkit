import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:psdkit/src/model.dart';

part 'layer_options/artboards.dart';
part 'layer_options/blending.dart';

/// Looks up the last tagged block stored under a key.
typedef PsdTaggedBlockLookup = PsdTaggedBlock? Function(String key);

/// How deeply a layer punches through the layers below it.
enum PsdKnockout {
  /// Blends normally with the layers below.
  none,

  /// Reveals the bottom of the enclosing group.
  shallow,

  /// Reveals the document background.
  deep,
}

/// Photoshop's color label shown in the Layers panel.
enum PsdSheetColor {
  /// No label.
  none(0),

  /// Red label.
  red(1),

  /// Orange label.
  orange(2),

  /// Yellow label.
  yellow(3),

  /// Green label.
  green(4),

  /// Blue label.
  blue(5),

  /// Violet label.
  violet(6),

  /// Gray label.
  gray(7);

  /// Index stored in the `lclr` block.
  final int code;

  /// Creates a label stored as [code].
  const PsdSheetColor(this.code);

  /// Returns the label stored as [code], or `null` for a newer label.
  static PsdSheetColor? fromCode(int code) {
    for (final PsdSheetColor color in values) {
      if (color.code == code) {
        return color;
      }
    }
    return null;
  }
}
