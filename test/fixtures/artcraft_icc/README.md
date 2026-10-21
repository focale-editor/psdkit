# ArtCraft ICC corpus

Seven unmodified CC0 profiles from https://github.com/storytold/craft-libs.
`manifest.json` pins each source path, commit, Git blob, SHA-256 and ICC header.
`UPSTREAM-NOTICE` retains authorship and source details; `LICENSE-CC0` is the
upstream profile license. The Compact ICC Profiles originate with Clinton Ingram.

The two generated CMYK profiles exercise LUT tables; the compact profiles cover
CMYK, RGB and gray in ICC v2/v4. They are test data, not recommended print profiles.
The corpus is excluded from pub.dev. Copies in the codec repositories let each
repository test profile preservation independently, without sibling checkouts.
