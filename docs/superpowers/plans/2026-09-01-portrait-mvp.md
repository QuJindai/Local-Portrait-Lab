# Portrait MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first Android-local portrait loop: import a portrait, choose a style, run real Local-Diffusion img2img with real progress, save the result, and retain a local history record.

**Architecture:** Keep Portrait Lab code as a focused overlay on locked upstream `rmatif/Local-Diffusion@184b7f92cf2f810e7d5eb4b04b190a5da829005f`. Domain/application code is independent of FFI; `LocalDiffusionPortraitEngine` adapts the upstream `Img2ImgProcessor` only at the infrastructure boundary. CI bootstraps upstream, applies the overlay, then runs Flutter analysis/tests/build.

**Tech Stack:** Flutter/Dart, Android arm64, Local-Diffusion, stable-diffusion.cpp FFI, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-01-portrait-lab-design.md`

## Global Constraints

- Locked upstream commit: `184b7f92cf2f810e7d5eb4b04b190a5da829005f`.
- V1 image generation is local-only; no remote inference client.
- Generation percentage must be derived from real runtime callbacks.
- UI does not call FFI directly.
- Original user portrait is never committed as test data.
- First device acceptance target is S24U / Android arm64.

---

### Task 1: Reproducible upstream bootstrap and CI harness

**Files:**
- Create: `scripts/bootstrap_upstream.sh`
- Create: `.github/workflows/portrait-mvp.yml`
- Create: `overlay/README.md`

**Interfaces:**
- Consumes: locked upstream commit.
- Produces: `_build/local-diffusion/` containing upstream plus the repository overlay.

- [ ] **Step 1: Write bootstrap contract check**

CI must reject a checkout that is not the locked upstream commit:

```bash
actual="$(git -C "$UPSTREAM_DIR" rev-parse HEAD)"
test "$actual" = "184b7f92cf2f810e7d5eb4b04b190a5da829005f"
```

- [ ] **Step 2: Implement bootstrap**

```bash
git clone https://github.com/rmatif/Local-Diffusion.git "$UPSTREAM_DIR"
git -C "$UPSTREAM_DIR" checkout --detach 184b7f92cf2f810e7d5eb4b04b190a5da829005f
cp -a overlay/lib/. "$UPSTREAM_DIR/lib/" 2>/dev/null || true
cp -a overlay/test/. "$UPSTREAM_DIR/test/" 2>/dev/null || true
```

- [ ] **Step 3: CI baseline**

Workflow steps: checkout → Flutter 3.x stable → bootstrap → `flutter pub get` → `flutter analyze` → `flutter test`.

- [ ] **Step 4: Commit**

```bash
git add scripts .github overlay/README.md
git commit -m "ci: add reproducible Local-Diffusion bootstrap"
```

---

### Task 2: RED — portrait domain/controller contract

**Files:**
- Create: `overlay/test/portrait_lab/portrait_generation_controller_test.dart`

**Interfaces:**
- Consumes later production types: `PortraitStyle`, `PortraitGenerationRequest`, `PortraitGenerationController`, `PortraitGenerationEngine`.
- Produces: executable behavioral contract.

- [ ] **Step 1: Write failing test for missing portrait**

```dart
test('generate rejects an empty portrait source', () async {
  final controller = PortraitGenerationController(FakePortraitEngine());
  expect(
    () => controller.generate(
      portraitPath: '',
      modelPath: '/models/model.safetensors',
      style: PortraitStyle.japaneseFresh,
    ),
    throwsA(isA<PortraitInputException>()),
  );
});
```

- [ ] **Step 2: Write failing test for style→request mapping**

```dart
test('japanese fresh preset maps deterministic generation values', () {
  final request = PortraitGenerationRequest.fromStyle(
    portraitPath: '/tmp/person.jpg',
    modelPath: '/models/model.safetensors',
    style: PortraitStyle.japaneseFresh,
  );
  expect(request.steps, greaterThan(0));
  expect(request.strength, inInclusiveRange(0.0, 1.0));
  expect(request.prompt, contains('portrait'));
});
```

- [ ] **Step 3: Write failing progress/cancel tests**

Assert `sampling(1, 4)` precedes `sampling(4, 4)`, and a cancellation prevents a later `completed` state.

- [ ] **Step 4: Push RED commit and observe Actions FAIL**

Expected failure: missing `portrait_lab` production imports/types.

- [ ] **Step 5: Commit**

```bash
git add overlay/test
git commit -m "test: define portrait generation controller contract"
```

---

### Task 3: GREEN — minimal portrait domain and controller

**Files:**
- Create: `overlay/lib/portrait_lab/domain/portrait_style.dart`
- Create: `overlay/lib/portrait_lab/domain/portrait_generation_request.dart`
- Create: `overlay/lib/portrait_lab/domain/portrait_generation_state.dart`
- Create: `overlay/lib/portrait_lab/application/portrait_generation_engine.dart`
- Create: `overlay/lib/portrait_lab/application/portrait_generation_controller.dart`

**Interfaces:**
- `PortraitGenerationEngine.generate(PortraitGenerationRequest request, void Function(PortraitGenerationState) onState)`.
- `PortraitGenerationController.generate({required String portraitPath, required String modelPath, required PortraitStyle style})`.
- `PortraitGenerationController.cancel()`.

- [ ] **Step 1: Implement immutable style presets**

Eight configuration-backed presets with prompt suffix, negative prompt, strength, CFG, steps, dimensions.

- [ ] **Step 2: Implement request validation/mapping**

Empty portrait path → `PortraitInputException`; empty model path → `PortraitModelException`.

- [ ] **Step 3: Implement state controller**

Controller publishes only legal ordered states and ignores completion after cancellation.

- [ ] **Step 4: Run tests**

```bash
flutter test test/portrait_lab/portrait_generation_controller_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add overlay/lib/portrait_lab
git commit -m "feat: add portrait generation domain and controller"
```

---

### Task 4: Local-Diffusion img2img adapter

**Files:**
- Create: `overlay/test/portrait_lab/local_diffusion_portrait_engine_test.dart`
- Create: `overlay/lib/portrait_lab/infrastructure/local_diffusion_portrait_engine.dart`

**Interfaces:**
- Consumes upstream `Img2ImgProcessor.generateImg2Img(...)`.
- Produces `PortraitGenerationEngine` implementation.

- [ ] **Step 1: RED test event mapping**

Use a fake upstream bridge to emit model-loaded, progress, image-result, and error events; assert mapping to Portrait Lab states.

- [ ] **Step 2: Verify RED**

Expected: adapter class missing.

- [ ] **Step 3: Implement bridge**

Map request fields to upstream img2img: input image bytes/dimensions, prompt/negative prompt, strength, CFG, steps, target dimensions, seed. Map upstream progress callbacks to `sampling(step, steps)` and generation result to `completed`.

- [ ] **Step 4: Verify GREEN**

Run all portrait tests and `flutter analyze`.

- [ ] **Step 5: Commit**

```bash
git add overlay/lib/portrait_lab/infrastructure overlay/test/portrait_lab
git commit -m "feat: adapt Local-Diffusion img2img for portrait generation"
```

---

### Task 5: P01–P04 usable loop

**Files:**
- Create: `overlay/test/portrait_lab/portrait_flow_widget_test.dart`
- Create: `overlay/lib/portrait_lab/ui/portrait_home_page.dart`
- Create: `overlay/lib/portrait_lab/ui/portrait_style_page.dart`
- Create: `overlay/lib/portrait_lab/ui/portrait_generation_page.dart`
- Create: `overlay/lib/portrait_lab/ui/portrait_result_page.dart`
- Create: `overlay/lib/portrait_lab/portrait_lab_app.dart`
- Modify via overlay/patch: upstream entry route in `lib/main.dart`.

**Interfaces:**
- P01 passes selected image/model to P02.
- P02 selects `PortraitStyle` and starts controller.
- P03 renders controller states/progress and cancellation.
- P04 receives generated image path and exposes save/regenerate.

- [ ] **Step 1: RED widget navigation test**

Test P01 → P02 → P03 with fake engine, then fake completion → P04.

- [ ] **Step 2: Implement P01–P04 using approved prototype structure**

No decorative fake states; progress uses controller stream only.

- [ ] **Step 3: Add Android build gate**

CI adds:

```bash
flutter build apk --debug --target-platform android-arm64
```

- [ ] **Step 4: Verify CI**

Expected: analyze PASS, unit/widget tests PASS, arm64 debug APK PASS.

- [ ] **Step 5: Commit**

```bash
git add overlay .github/workflows/portrait-mvp.yml
git commit -m "feat: complete portrait P01-P04 local generation loop"
```

---

### Task 6: P05 history and P06 local model management

**Files:**
- Create tests and `portrait_history_service.dart`, `portrait_history_page.dart`, `portrait_models_page.dart`.

**Interfaces:**
- History stores generated output path + minimal generation metadata only.
- Model page initially reuses local model selection/availability; online model catalog/download is not a V1 gate.

- [ ] RED tests for save/list/delete and missing-file cleanup.
- [ ] GREEN implementation.
- [ ] Widget navigation tests for P05/P06.
- [ ] Full Flutter tests/build.
- [ ] Commit `feat: add local portrait history and model management`.

---

### Task 7: S24U handset acceptance

**Evidence:**
- One source portrait × at least three presets.
- Airplane mode generation.
- Save to gallery/history.
- No crash.
- Record model, resolution, steps, elapsed time, peak memory, thermal state.

This is device-only and is not replaced by CI.
