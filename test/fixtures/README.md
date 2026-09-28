# Filter-effect interoperability fixture

`filter_effects_1.base64` is the unchanged base64 encoding of
[`tests/tagged_blocks/filter_effects_1.dat`](https://github.com/psd-tools/psd-tools/blob/main/tests/tagged_blocks/filter_effects_1.dat)
from psd-tools. It contains a real version-3 Photoshop filter-effect cache and
a nonuniform shared mask, including negative and independently sized bounds.
Tests verify the complete binary round trip and sample counts independently
checked with psd-tools. The fixture is not a complete PSD document.

Source: https://github.com/psd-tools/psd-tools
License: MIT; see `psd-tools-LICENSE.txt` beside this file.
