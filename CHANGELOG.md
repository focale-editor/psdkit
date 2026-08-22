# PsdKit changelog

## Unreleased

- Fixed PackBits encoding when a two-byte literal run crossed the 128-byte packet boundary.
- Implemented Photoshop's byte-plane shuffle for 32-bit ZIP prediction.
- Bounded zlib expansion before allocating a complete decoded channel.
- Reduced peak import memory by using bounded byte views for nested sections and compressed payloads.
- Decoded and regenerated depth-specific `Layr`, `Lr16`, and `Lr32` layer information instead of retaining it only as opaque data.
- Added action-descriptor object arrays (`ObAr`) and unit-float arrays (`UnFl`) used by warped smart objects.
- Added complete-document corpus round-trip auditing.
