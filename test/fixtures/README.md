# Photoshop interoperability fixtures

`filter_effects_1.base64` is the unchanged base64 encoding of
[`tests/tagged_blocks/filter_effects_1.dat`](https://github.com/psd-tools/psd-tools/blob/main/tests/tagged_blocks/filter_effects_1.dat)
from psd-tools. It contains a real version-3 Photoshop filter-effect cache and
a nonuniform shared mask, including negative and independently sized bounds.
Tests verify the complete binary round trip and sample counts independently
checked with psd-tools. The fixture is not a complete PSD document.

Source: https://github.com/psd-tools/psd-tools
License: MIT; see `psd-tools-LICENSE.txt` beside this file.

## Layer masks

`layer_mask_data.base64` is the unchanged base64 encoding of
[`tests/psd_files/layer_mask_data.psd`](https://github.com/psd-tools/psd-tools/blob/main/tests/psd_files/layer_mask_data.psd)
from the same MIT-licensed repository, retrieved on 2026-10-09.

- Git blob: `9e1ee6f835aa0f1f016a9eaa1e4ea49b094dfb24`.
- Source SHA-256: `e30f5d2f51ef2dc5790b45b50ff3911ab7991ffdf63230561364a2574c1392aa`.

This complete PSD contains five layers, raster masks with optional density and
feather parameters, and a separate real-mask channel. The regression test checks
its independently sized rectangles, sample counts, and channel preservation
through a document round trip. It does not assert complete file byte equality.

## Adjustment layers

`adjustment_layers.base64` is the unchanged base64 encoding of
[`test/read/adjustment-layers/src.psd`](https://github.com/Agamnentzar/ag-psd/blob/master/test/read/adjustment-layers/src.psd)
from ag-psd, retrieved on 2026-10-10.

- Source SHA-256: `60a8e5f4226345bc5adc8ea6a1ce2f65c36ff03000fdb94be98c8931a71c7bc2`.

Photoshop saved this document with one layer per adjustment type. The test
checks values against ag-psd's expected `data.json`: brightness/contrast read
from the `CgEd` descriptor, floating-point exposure, and the gradient map.

Source: https://github.com/Agamnentzar/ag-psd
License: MIT; see `ag-psd-LICENSE.txt` beside this file.
