# PhotoCraft Photoshop reference corpus

The `photocraft/` files originate from
https://github.com/storytold/photocraft-corpus at commit
`0d3343b04edda369e277572d4c65ea97bba25b1f`.

The 258 PSD files were generated in Adobe Photoshop by PhotoCraft's scripts.
They include Photoshop's own merged image and cover adjustments, effects,
smart filters and text. They are redistributed under the upstream
MIT OR Apache-2.0 license; the original license files and NOTICE are included.
`photocraft/manifest.json` records each path, byte length, Git blob hash and
SHA-256 digest. All downloads were checked against the pinned Git tree.

The HDR record layout and Txt2 field interpretation used by PsdKit were
informed by PhotoCraft at commit `6d8cbac7dcc4a2c8a32e0ceefe637cd72c98da32`:
https://github.com/storytold/photocraft/tree/6d8cbac7dcc4a2c8a32e0ceefe637cd72c98da32

These tests check file structures, sample precision and serialization. They do
not assert Focale rendering equivalence or acceptance of edited files by a
running copy of Photoshop. The corpus is excluded from the pub.dev archive.
