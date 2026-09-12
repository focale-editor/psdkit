# 📰 PsdKit changelog

## v0.3.5
Released on September 12, 2026.

* **DOCS**: Moved technical reference to docs/PSD.md and streamlined README. ([#431739c](https://github.com/focale-editor/psdkit/commit/431739c))
* **FEAT**: Added legacy type-tool support, global text engine data, and expanded text formatting semantics. ([#060a2ee](https://github.com/focale-editor/psdkit/commit/060a2ee))
* **FEAT**: Added text shape metadata presence tracking and improved text descriptor fallbacks. ([#02eb6c7](https://github.com/focale-editor/psdkit/commit/02eb6c7))
* **FIX**: Fixed legacy layer effects decoding, engine data parser limits, and pixel conversion performance. ([#8c57784](https://github.com/focale-editor/psdkit/commit/8c57784))
* **FIX**: Fixed paragraph justification mapping and trailing paragraph mark handling in text engine data. ([#8866572](https://github.com/focale-editor/psdkit/commit/8866572))
* **CHORE**: Updated `pscore`. ([#4c90a49](https://github.com/focale-editor/psdkit/commit/4c90a49))

## v0.3.4
Released on September 6, 2026.

* **FIX**: Fixed various problems for decoding trailing styles data. ([#1be0839](https://github.com/focale-editor/psdkit/commit/1be0839))

## v0.3.3
Released on September 6, 2026.

* **FEAT**: Added seekable, bounded-memory RAW and PackBits writing for PSD and PSB documents. ([#5ac8563](https://github.com/focale-editor/psdkit/commit/5ac8563))

## v0.3.2
Released on September 5, 2026.

* **FEAT**: Added support for per-layer composition metadata. ([#1bd7f20](https://github.com/focale-editor/psdkit/commit/1bd7f20))

## v0.3.1
Released on September 3, 2026.

* **FEAT**: Added smart filters support. ([#b9d1873](https://github.com/focale-editor/psdkit/commit/b9d1873))

## v0.3.0
Released on August 29, 2026.

* **BREAKING CHORE**: Now using the latest version of `zcodec`. ([#3d9a02a](https://github.com/focale-editor/psdkit/commit/3d9a02a))

## v0.2.1
Released on August 25, 2026.

* **REFACTOR**: Now using paths from `pscore`. ([#8a57716](https://github.com/focale-editor/psdkit/commit/8a57716))

## v0.2.0
Released on August 25, 2026.

* **BREAKING REFACTOR**: Now using `pscore` to share primitives among other PS-Dart libraries. ([#e5be588](https://github.com/focale-editor/psdkit/commit/e5be588))

## v0.1.0
Released on August 23, 2026.

* **Initial release**.
