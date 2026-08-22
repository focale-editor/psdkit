# Integrating PsdKit into Focale

PsdKit should remain a format library. Focale owns conversion between `PsdDocument` and its `FocaleDocument`, `LayerNode`, `ImageEngine`, adjustment, text, path, and style types.

## Dependency

During local development, add the sibling package to Focale:

```yaml
dependencies:
  psdkit:
    path: ../psdkit
```

The package has no runtime dependency of its own.

## Import pipeline

Create a `PsdImportService` in Focale's documents data layer. It should perform `PsdCodec.decode` in an isolate, then map the result as follows:

| PsdKit | Focale |
|---|---|
| Canvas width and height | `FocaleDocument.width` and `height` |
| Regular record with colour channels | `RasterLayer` plus an engine raster asset |
| `rectangle.left` and `rectangle.top` | Layer translation |
| Opacity byte | `opacity / 255` |
| Blend-mode key | `LayerBlendMode` mapping |
| Hidden flag | `visible: false` |
| Channel `-1` | Raster alpha |
| Channel `-2` and mask rectangle | Mask asset and `maskOffset` |
| `openFolder` / `closedFolder` and `boundingDivider` | `GroupLayer` boundaries |
| `layer.typeTool?.content.text` | `TextContent.text` |
| `PsdTextStyleRun` | `TextStyleRange` |
| Font family, size, faux bold/italic, decorations | Corresponding `TextContent` and `TextStyleRange` properties |
| `PsdTextColor.argb` | Focale text color |
| Tracking, leading, orientation, and paragraph alignment | Corresponding text-layout properties where available |
| `PsdLayer.effects.effects` | Focale layer styles/effects |
| `PsdLayerEffectType` | Shadow, glow, stroke, overlay, bevel, and satin effect types |
| Effect color, opacity, blend mode, size, angle, distance, spread, and noise | Corresponding Focale effect properties |
| `PsdEffectGradient` and `PsdEffectPattern` | Gradient and pattern effect resources |
| Adjustment, fill, and vector-mask blocks | Corresponding semantic Focale layer data where supported |

`PsdPixels.decodeLayer(document, layer)` provides straight-alpha RGBA bytes for an initial raster adapter. Register the resulting `ui.Image` through `ImageEngine.adoptImage`. PSD layer records and Focale child ids both use topmost-first paint order, but group divider records must be consumed rather than exposed as visible layers.

For best round-trip fidelity, Focale should retain the original `PsdImageResource` list and unsupported `PsdTaggedBlock` values in import metadata. When an imported feature remains unchanged, export its retained block. When Focale edits a feature it understands, regenerate that block from Focale's semantic model.

For imported text, retain the complete `PsdTypeTool`. If only the characters change, call `typeTool.withText(newText)`; this preserves unknown Adobe engine keys and extends or truncates the final style and paragraph runs as needed. If formatting changes, map Focale's style ranges to `PsdTextContent` and call `typeTool.withContent(content)`.

For imported effects, retain the complete `PsdLayerEffects` and each effect's `descriptor`. Common properties are exposed directly and can be updated with `withEnabled`, `withOpacity`, `withColor`, or `withProperty`. Call `layer.withEffects(updatedEffects)` only when the Focale effect model changed; untouched `lfx2`, `lmfx`, and `lrFX` blocks remain byte-stable.

## Export pipeline

Create a `PsdExportService` in Focale's export data layer:

1. Render the full document once at export quality for `PsdDocument.mergedImage`.
2. Snapshot raster assets and request `ui.ImageByteFormat.rawStraightRgba`.
3. Use `PsdPixels.encodeRgb` and assign PSD channel ids `0`, `1`, `2`, and `-1`.
4. Convert Focale's topmost-first layer tree into flat PSD records, inserting an `lsct` start record and a hidden bounding-divider record around each group.
5. Map blend modes, opacity, visibility, lock flags, masks, ids, text, paths, adjustments, fills, and styles.
6. Preserve retained resources and unsupported tagged blocks.
7. Select PSB automatically when either dimension exceeds 30,000 pixels or a PSD section cannot fit in 32 bits.
8. Run `PsdCodec.encode` in an isolate and let Focale's file store perform the final atomic write.

PsdKit requires the merged image explicitly because compositing belongs to Focale's renderer. This keeps blend-mode and adjustment rendering consistent with what the user sees instead of embedding a second compositor in the file-format package.

For a new Focale text layer, create `PsdTextContent`, call `PsdTypeTool.fromText`, and attach it with `PsdLayer.withTypeTool`. The PSD layer must still contain Focale-rendered RGB/alpha preview channels, and the document merged image must include the rendered text. Photoshop uses those pixels when editable text cannot be rendered locally, while `TySh` keeps the content editable.

For new layer effects, create one or more `PsdLayerEffect` values, group them with `PsdLayerEffects.create`, and attach them through `PsdLayer.withEffects`. Multiple effects of the same family are emitted through Photoshop's multi-effect descriptor keys automatically. As with text, Focale should render the resulting appearance into the layer channels and merged image.

## Initial rollout

An incremental integration can first import every visible record as a raster layer while retaining all opaque blocks. A second phase can map groups and masks, followed by editable text and layer effects, then shapes and adjustments. The retained blocks keep unsupported features available for later semantic support and reduce destructive round trips during that rollout.
