/// Prints structural information about a PSD or PSB file.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';

/// Decodes the first command-line path and prints its document summary.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/psd_info.dart <file.psd|file.psb>');
    exitCode = 64;
    return;
  }
  final Uint8List bytes = await File(arguments.single).readAsBytes();
  final PsdDocument document = PsdCodec.decode(bytes);
  stdout.writeln(
    '${document.version.name.toUpperCase()} ${document.width}x${document.height} '
    '${document.depth}-bit ${document.colorMode.name}, ${document.layers.length} layers, ${document.channels} merged channels',
  );
  final PsdRgbaImage preview = PsdPixels.decodeMerged(document);
  stdout.writeln('  first RGBA pixel: ${preview.bytes.take(4).join(', ')}');
  for (final PsdLayer layer in document.layers) {
    stdout.writeln('  ${layer.name}: ${layer.rectangle.width}x${layer.rectangle.height}, ${layer.channels.length} channels, ${layer.sectionType.name}');
    stdout.writeln('    tagged blocks: ${layer.additionalInfo.map((block) => block.key).join(', ')}');
    final PsdTypeTool? text = layer.typeTool;
    if (text != null) {
      stdout.writeln('    text: ${text.text.replaceAll('\r', r'\r').replaceAll('\n', r'\n')}');
      stdout.writeln('    descriptor keys: ${text.textDescriptor.items.map((item) => item.key).join(', ')}');
      final PsdTextContent content = text.content;
      for (final PsdTextStyleRun run in content.styleRuns) {
        stdout.writeln(
          '    style ${run.start}..${run.start + run.length}: '
          '${run.style.fontFamily ?? '-'} ${run.style.fontSize ?? '-'} pt, '
          'ARGB ${run.style.color?.argb.toRadixString(16).padLeft(8, '0') ?? '-'}',
        );
      }
      for (final PsdTextParagraph paragraph in content.paragraphs) {
        stdout.writeln(
          '    paragraph ${paragraph.start}..${paragraph.start + paragraph.length}: '
          '${paragraph.justification.name}',
        );
      }
    } else if (layer.taggedBlock('TySh') != null) {
      stdout.writeln('    text: unsupported or malformed TySh payload');
    }
    final PsdLayerEffects? effects = layer.effects;
    if (effects != null) {
      stdout.writeln('    effects: ${effects.effects.length}, enabled=${effects.enabled}, scale=${effects.scale}');
      for (final PsdLayerEffect effect in effects.effects) {
        stdout.writeln(
          '      ${effect.type.name}: enabled=${effect.enabled}, blend=${effect.blendMode}, '
          'opacity=${effect.opacity}, color=${effect.color?.argb.toRadixString(16) ?? '-'}, size=${effect.size ?? '-'}',
        );
      }
    }
  }
}
