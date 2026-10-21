# Independent layered TIFF corpus

Generated with PhotoCraft's script at 43b14883253af3ddf5f7f35038aec0adb0959959:
https://github.com/storytold/photocraft/blob/43b14883253af3ddf5f7f35038aec0adb0959959/scripts/layered_tiff_fixtures.py
Copyright (c) 2026 ArtCraft Team and the PhotoCraft contributors, MIT OR Apache-2.0.
Only the script's output directory was changed. The license texts are included.

Reproduce in a virtual environment with `pip install -r requirements.txt`, then
`python generate.py`. The Python packages are only needed for regeneration.
The independent writers are psdtags and tifffile, not PsdKit or Imcodec.

The four files cover both TIFF/private-tag byte orders at 8/16 bits. Each contains
a 6x4 RGBA composite and two layers: Background (6x4, RLE) and Upper é (4x3,
offset 1,1, ZIP, Multiply, opacity 200, varying alpha), plus a user mask.
The composite is the background ramp, deliberately not a flattened rendering of
both layers. Tests compare the exact generated samples, not compositing fidelity.
`manifest.json` records the file and tag 37724 hashes. Files are excluded from pub.dev.
