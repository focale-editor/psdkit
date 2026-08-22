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
    } else if (layer.taggedBlock('TySh') case final PsdTaggedBlock block) {
      try {
        PsdTypeToolCodec.decode(block.data);
      } on Object catch (error) {
        stdout.writeln('    text decode error: $error');
        final ({PsdDescriptor descriptor, int bytesRead}) textDescriptor = PsdDescriptorCodec.decodePrefix(Uint8List.sublistView(block.data, 56));
        final int warpOffset = 56 + textDescriptor.bytesRead + 6;
        final ({PsdDescriptor descriptor, int bytesRead}) warpDescriptor = PsdDescriptorCodec.decodePrefix(Uint8List.sublistView(block.data, warpOffset));
        stdout.writeln(
          '    TySh bytes: ${block.data.length}, text descriptor: ${textDescriptor.bytesRead}, '
          'warp descriptor: ${warpDescriptor.bytesRead}, bounds bytes: ${block.data.length - warpOffset - warpDescriptor.bytesRead}',
        );
      }
    }
  }
}
