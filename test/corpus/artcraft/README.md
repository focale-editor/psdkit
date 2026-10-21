# Additional PSD and PSB corpus

39 unmodified files selected from PhotoCraft's pinned psd-tools and ag-psd
manifests. `manifest.json` records the selection revision, original repositories,
commits, paths, sizes, SHA-256 hashes and independently read PSD headers.
The upstream MIT licenses are retained in each source directory.

Selection covers every small colormodes fixture, PSD/PSB 16/32-bit samples,
grouping, raster/vector masks, a mask without a real channel, metadata, GIMP
output, spot channels, multichannel patterns, Unicode names, animation,
annotations, layer comps and text boxes. Source fixtures are preferred over
ag-psd's generated expected files. SHA-256 deduplication includes the existing
PhotoCraft corpus and the overlapping upstream lists.

`reference.json` records layer metadata and decoded plane hashes from the
independent psd-tools 1.26.0 reader. Reproduce with `pip install psd-tools==1.26.0`
and `python generate_reference.py`. Empty group channels have no pixel bytes;
mask channels are checked during round-trips rather than hashed by this oracle.

Tests check the recorded headers, eager/lazy decoding and preservation of pixels,
resources and layer records across serialization. These are structural tests,
not proof of Photoshop acceptance or rendering equivalence. Fixtures are checked
in for offline tests and excluded from the pub.dev archive.
