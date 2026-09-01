# Local Portrait Lab Design

## Goal

Turn the approved six-page Portrait Lab prototype into a real Android local-image-generation application. The first shippable gate is: import one portrait photo → select a style → execute real on-device img2img → display real progress → save the generated image → view it in history.

## Product baseline

The approved product structure is frozen for V1:

1. P01 Creation home — portrait photo, image quality state, style entry, aspect ratio.
2. P02 Style selection — style direction, expression, generated prompt preset.
3. P03 Local generation — actual execution stage/progress, elapsed time, cancel.
4. P04 Result/refine — inspect, save, regenerate, continue refinement.
5. P05 History — local generated work index.
6. P06 Model management — local model state and capabilities.

V1 does not require an account, remote inference, or uploading user portraits/results.

## Technical baseline

- Flutter Android application.
- Upstream runtime: `rmatif/Local-Diffusion`.
- Locked upstream commit: `184b7f92cf2f810e7d5eb4b04b190a5da829005f`.
- Native engine: `stable-diffusion.cpp` through the upstream FFI/isolate integration.
- Existing upstream capability reused: `Img2ImgProcessor.generateImg2Img(...)`, progress/log callbacks, image picking/saving, model loading.
- First device gate: Android arm64, S24U.

## Repository strategy

The repository keeps our Portrait Lab code as a small, reviewable overlay rather than copying upstream giant UI files. CI/reproducible build scripts clone the locked upstream commit, overlay Portrait Lab sources/tests, and build the resulting Flutter Android application. This preserves upstream traceability and makes future upstream rebases explicit.

## New module boundaries

`lib/portrait_lab/` is separated into:

- `domain/`: immutable style/request/state/result value objects.
- `application/`: controller/state machine and use-case policy.
- `infrastructure/`: Local-Diffusion img2img adapter and local history storage.
- `ui/`: P01–P06 screens.
- `widgets/`: reusable presentation components.

UI must never call native FFI directly. The application controller depends on a `PortraitGenerationEngine` interface; production uses the Local-Diffusion adapter, tests use a deterministic fake engine.

## First milestone data flow

```text
portrait file
  → decode/validate/orient
  → style preset
  → PortraitGenerationRequest
  → PortraitGenerationController
  → LocalDiffusionPortraitEngine
  → Img2ImgProcessor.generateImg2Img(...)
  → real progress events
  → decoded generated image
  → local save
  → history record
```

## Generation state machine

```text
idle
 → preparing
 → loadingModel
 → encodingInput
 → sampling(step/steps)
 → decoding
 → saving
 → completed
```

Terminal/error states:

- `cancelled`
- `modelMissing`
- `modelUnsupported`
- `outOfMemory`
- `inputInvalid`
- `nativeFailure`
- `saveFailure`

A screen percentage can only be derived from real runtime stage/step callbacks. No timer-driven fake progress.

## Style presets

Initial presets are configuration-backed, not hard-coded into widgets:

- Japanese fresh
- Anime illustration
- Manga
- Business portrait
- Cinematic portrait
- Editorial/magazine
- Ancient Chinese style
- Cyberpunk

Each preset owns `id`, display name, prompt suffix, negative prompt, strength, CFG, steps, dimensions, and recommended model family.

## Privacy and storage

- Original portrait remains local.
- Generation working copies use application cache.
- Cache is cleaned after completion/cancel where safe.
- History only stores generated outputs explicitly retained by the user plus minimum reproducibility metadata.
- V1 contains no server inference client.

## Testing gates

- G0: Flutter analyze/test pass, no accidental user image fixtures.
- G1: domain/controller TDD covers missing input/model, request mapping, real progress ordering, cancellation, error mapping.
- G2: widget navigation covers the six primary screens.
- G3: arm64 debug/release APK builds and launches without crash.
- G4: S24U airplane-mode acceptance with at least one source portrait × three styles, output save, elapsed time/memory/thermal evidence.

## Scope order

1. Repository/bootstrap/CI.
2. Portrait domain + controller using RED→GREEN TDD.
3. Local-Diffusion img2img adapter.
4. P01–P04 real end-to-end loop.
5. P05 history.
6. P06 model management.
7. S24U performance and identity-preservation experiments (PhotoMaker/IP-Adapter only after the base loop is stable).
