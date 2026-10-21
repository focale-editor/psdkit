"""Regenerate structural/pixel oracles with psd-tools==1.26.0, not PsdKit."""

import hashlib
import json
from importlib.metadata import version
from pathlib import Path

from psd_tools import PSDImage
from psd_tools.constants import Tag

ROOT = Path(__file__).resolve().parent


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    assert version('psd-tools') == '1.26.0'
    manifest = json.loads((ROOT / 'manifest.json').read_text())
    references = {}
    for entry in manifest['files']:
        path = ROOT / entry['path']
        assert digest(path.read_bytes()) == entry['sha256']
        document = PSDImage.open(path)
        record = document._record
        info = record._get_layer_info()
        layers = []
        if info is not None:
            for layer, channels in zip(info.layer_records, info.channel_image_data):
                layers.append(dict(
                    name=layer.tagged_blocks.get_data(Tag.UNICODE_LAYER_NAME, layer.name),
                    rectangle=[layer.top, layer.left, layer.bottom, layer.right],
                    opacity=layer.opacity, blendMode=layer.blend_mode.value.decode('ascii'),
                    flags=layer.flags.tobytes()[0], clipping=int(layer.clipping),
                    channels=[dict(id=int(channel.id), **(
                        dict(sha256=digest(data.get_data(layer.width, layer.height,
                            document.depth, record.header.version) if layer.width and layer.height else b''))
                        if channel.id >= -1 else {}))
                        for channel, data in zip(layer.channel_info, channels)],
                ))
        references[entry['path']] = dict(layers=layers, mergedSha256=[
            digest(plane) for plane in record.image_data.get_data(record.header)])
    (ROOT / 'reference.json').write_text(json.dumps(dict(
        generator='psd-tools==1.26.0', files=references), ensure_ascii=False, indent=2)+'\n')


if __name__ == '__main__':
    main()
