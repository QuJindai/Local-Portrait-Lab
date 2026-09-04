# Portrait Lab R11 On-Device Identity Lock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the existing QNN/HTP SDXL-DMD2 style-generation path and add a real on-device identity pipeline that detects the source face, extracts an ArcFace identity embedding, corrects the generated face with INSwapper, verifies identity with cosine similarity, and only then reports generation success.

**Architecture:** The existing backend router produces a temporary styled PNG. A new `IdentityLockedPortraitEngine` decorates that router and invokes an Android `identity_lock` MethodChannel. Android runs SCRFD, ArcFace and INSwapper through ONNX Runtime on a dedicated executor, blends only the face ROI, computes pre/post identity similarity, and returns a final PNG plus diagnostics. Third-party model weights are never committed to Git or bundled in the APK; the app downloads and SHA-256 verifies a research-use model pack into app-private storage.

**Tech Stack:** Flutter/Dart, Android Kotlin/Java, ONNX Runtime Android 1.29.0, SCRFD `det_10g.onnx`, ArcFace `w600k_r50.onnx`, INSwapper `inswapper_128.onnx`, existing QNN/HTP Local Dream backend.

**Spec:** `docs/superpowers/specs/2026-09-04-portrait-identity-lock-design.md`

## Global Constraints

- Target device is Samsung S24U / Android arm64.
- Existing QNN/DMD2 generation remains localhost-only at `127.0.0.1:8082`.
- Identity lock is enabled by default with `strength=0.88`, `minSimilarity=0.40`, `minImprovement=0.08`.
- Source photos and face embeddings never leave the device.
- Face embeddings are not persisted in history; only QA scores/model-pack version may be persisted or displayed.
- A QA failure must not enter `PortraitGenerationCompleted`.
- No InsightFace/INSwapper ONNX weights may be committed to this public repository or bundled in the APK.
- Third-party model use must be labeled research/evaluation; commercial model rights are not implied.
- All network, ONNX and heavy bitmap work must run off the Android UI thread.

---

### Task 1: Freeze the Dart identity contract with failing tests

**Files:**
- Create: `overlay/lib/portrait_lab/domain/portrait_identity.dart`
- Modify: `overlay/lib/portrait_lab/domain/portrait_generation_request.dart`
- Modify: `overlay/lib/portrait_lab/domain/portrait_generation_state.dart`
- Create: `overlay/test/portrait_lab/portrait_r11_identity_lock_test.dart`

**Interfaces:**
- Produces: `PortraitIdentityPolicy`, `PortraitIdentityDiagnostics`, identity-specific generation states.
- `PortraitGenerationRequest.identityPolicy` defaults to `PortraitIdentityPolicy.standard`.

- [ ] **Step 1: Write the failing test**

The test must assert the standard policy values, that `fromStyle()` enables identity lock, and that identity states carry real diagnostics instead of fake progress.

- [ ] **Step 2: Run CI/Flutter test and verify RED**

Run: `flutter test test/portrait_lab/portrait_r11_identity_lock_test.dart`
Expected: FAIL because the R11 identity types do not exist yet.

- [ ] **Step 3: Implement the minimal Dart domain objects**

`PortraitIdentityPolicy.standard` must equal:

```dart
const PortraitIdentityPolicy(
  enabled: true,
  strength: 0.88,
  minSimilarity: 0.40,
  minImprovement: 0.08,
);
```

`PortraitIdentityDiagnostics` contains `preSimilarity`, `postSimilarity`, `improvement`, `lockMillis`, `packVersion`, and `passed`.

- [ ] **Step 4: Re-run the focused test**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add overlay/lib/portrait_lab/domain overlay/test/portrait_lab/portrait_r11_identity_lock_test.dart
git commit -m "feat: add R11 portrait identity contract"
```

---

### Task 2: Add the Android identity model-pack contract

**Files:**
- Modify: `overlay/android/app/build.gradle`
- Create: `overlay/android/app/src/main/kotlin/com/qujindai/localportraitlab/PortraitIdentityModelPack.kt`
- Create: `THIRD_PARTY_ANDROID_FACE_FUSION_MIT.md`
- Modify: `.github/workflows/portrait-mvp.yml`

**Interfaces:**
- Produces: `PortraitIdentityModelPack.ensureInstalled(progress)` returning the private model directory.
- Exact files and hashes:
  - `det_10g.onnx` → `5838f7fe053675b1c7a08b633df49e7af5495cee0493c7dcf6697200b85b5b91`
  - `w600k_r50.onnx` → `4c06341c33c2ca1f86781dab0e829f88ad5b64be9fba56e56bc9ebdefc619e43`
  - `inswapper_128.onnx` → `e4a3f08c753cb72d04e10aa0f7dbe3deebbf39567d4ead6dce08e98aa49e16af`

- [ ] **Step 1: Add static contract tests/checks**

CI must grep for the exact hashes, ONNX Runtime dependency and the absence of `.onnx` files under the repository/APK assets.

- [ ] **Step 2: Verify the contract check fails before implementation**

Expected: FAIL because model-pack code/dependency is absent.

- [ ] **Step 3: Add ONNX Runtime and Android settings**

Use Java 11, `minSdkVersion 26`, arm64 packaging, and:

```gradle
implementation "com.microsoft.onnxruntime:onnxruntime-android:1.29.0"
```

Keep the existing QNN native runtime intact.

- [ ] **Step 4: Implement private-storage downloads**

Use `.part` files, redirects/retries, resume when supported, SHA-256 verification before atomic rename, and explicit error state. Model URLs are runtime data; no model binary is committed.

- [ ] **Step 5: Add third-party notices**

Record the MIT source adaptation and explicit model-license warning.

- [ ] **Step 6: Re-run static checks**

Expected: PASS.

---

### Task 3: Implement on-device face detection and ArcFace identity math

**Files:**
- Create: `overlay/android/app/src/main/java/com/qujindai/localportraitlab/identity/PortraitOrtSessionHelper.java`
- Create: `overlay/android/app/src/main/java/com/qujindai/localportraitlab/identity/PortraitFaceDetector.java`
- Create: `overlay/android/app/src/main/java/com/qujindai/localportraitlab/identity/PortraitFaceImageUtils.java`
- Create: `overlay/android/app/src/main/java/com/qujindai/localportraitlab/identity/PortraitArcFaceEncoder.java`
- Create: `overlay/android/app/src/test/java/com/qujindai/localportraitlab/identity/PortraitIdentityMathTest.java`

**Interfaces:**
- `PortraitFaceDetector.detectFaces(Bitmap): List<Face>` where `Face` has bbox, five landmarks and confidence.
- `PortraitFaceImageUtils.alignFace(Bitmap,float[],int): Bitmap` supports 112 and 128 templates.
- `PortraitArcFaceEncoder.embedding(Bitmap): float[512]` returns L2-normalized embedding.
- `PortraitArcFaceEncoder.cosine(float[],float[]): float`.

- [ ] **Step 1: Write failing JVM tests for L2 normalization/cosine and face-selection policy**
- [ ] **Step 2: Verify RED**
- [ ] **Step 3: Adapt the MIT Android SCRFD/ArcFace implementation**

Use SCRFD 640 input, `(pixel-127.5)/128` detector normalization, ArcFace 112 input and `(pixel-127.5)/127.5` recognition normalization. Default single-person choice is largest face with a center-distance tie breaker.

- [ ] **Step 4: Verify focused Android tests/compile**
- [ ] **Step 5: Commit**

---

### Task 4: Implement INSwapper identity transfer and face-only blending

**Files:**
- Create: `overlay/android/app/src/main/java/com/qujindai/localportraitlab/identity/PortraitInSwapper.java`
- Extend: `overlay/android/app/src/main/java/com/qujindai/localportraitlab/identity/PortraitFaceImageUtils.java`
- Create: `overlay/android/app/src/main/kotlin/com/qujindai/localportraitlab/PortraitIdentityLockProcessor.kt`

**Interfaces:**
- `PortraitInSwapper.swapFace(target128, sourceEmbedding): Bitmap`.
- `PortraitIdentityLockProcessor.lock(sourcePath,targetPath,policy): LockResult`.
- `LockResult` fields: outputPath, preSimilarity, postSimilarity, improvement, lockMillis, packVersion, passed.

- [ ] **Step 1: Add failing contract/math tests for embedding transform and QA gate**
- [ ] **Step 2: Verify RED**
- [ ] **Step 3: Implement INSwapper path**

Use image input `[1,3,128,128]`, embedding input `[1,512]`, source embedding transform matrix, L2 normalization, inverse similarity transform and a face ROI feather mask.

The learned 512×512 INSwapper embedding map must be obtained at runtime with the model pack (not committed into the APK/repo) and verified like the ONNX files.

- [ ] **Step 4: Implement QA gate**

Normal pass:

```text
post >= minSimilarity && post - pre >= minImprovement
```

Already-good face exception:

```text
pre >= minSimilarity && post >= pre - 0.02
```

- [ ] **Step 5: Verify focused tests/Android compile**
- [ ] **Step 6: Commit**

---

### Task 5: Add the Android identity MethodChannel without UI-thread inference

**Files:**
- Modify: `overlay/android/app/src/main/kotlin/com/qujindai/localportraitlab/MainActivity.kt`
- Create: `overlay/android/app/src/main/kotlin/com/qujindai/localportraitlab/PortraitIdentityRuntime.kt`

**Interfaces:**
- Channel: `com.qujindai.localportraitlab/identity_lock`
- Methods:
  - `status`
  - `prepareModels`
  - `lock`
  - `cancel`
- `lock` returns a map matching `PortraitIdentityDiagnostics` plus `outputPath`.

- [ ] **Step 1: Add a static regression check that identity work is submitted to `identityExecutor`**
- [ ] **Step 2: Verify RED**
- [ ] **Step 3: Implement channel and dedicated executor**

No ONNX inference, file hashing, downloading or bitmap processing may occur in the MethodChannel callback thread.

- [ ] **Step 4: Verify Android compile/static regression check**
- [ ] **Step 5: Commit**

---

### Task 6: Decorate the QNN result with real identity lock

**Files:**
- Create: `overlay/lib/portrait_lab/infrastructure/portrait_identity_lock_engine.dart`
- Modify: `overlay/lib/portrait_lab/portrait_runtime.dart`
- Extend: `overlay/test/portrait_lab/portrait_r11_identity_lock_test.dart`

**Interfaces:**
- `AndroidPortraitIdentityLockClient.lock(sourcePath, styledPath, policy)`.
- `IdentityLockedPortraitEngine` wraps `PortraitBackendRouterEngine`.

- [ ] **Step 1: Write failing Dart behavior tests**

Cover:
1. QNN/base engine result is locked before return.
2. QA PASS returns locked output.
3. QA FAIL throws `PortraitIdentityLockException` and never returns the pre-lock image as success.
4. cancel cancels both base generation and identity lock.

- [ ] **Step 2: Verify RED**
- [ ] **Step 3: Implement the decorator and runtime wiring**
- [ ] **Step 4: Run all `test/portrait_lab` tests**
- [ ] **Step 5: Commit**

---

### Task 7: Replace fake identity UI with real identity stages and diagnostics

**Files:**
- Modify: `overlay/lib/portrait_lab/ui/portrait_generation_page.dart`
- Modify: `overlay/lib/portrait_lab/ui/portrait_result_page.dart`
- Extend: `overlay/test/portrait_lab/portrait_flow_widget_test.dart`
- Extend: `overlay/test/portrait_lab/portrait_r11_identity_lock_test.dart`

**Interfaces:**
- Generation page stages: analyze identity → QNN style generation → lock identity → verify identity → save.
- Result page shows `Identity PASS`, pre, post, delta, lock time and pack version for development diagnostics.

- [ ] **Step 1: Write failing widget tests for identity stages and diagnostic labels**
- [ ] **Step 2: Verify RED**
- [ ] **Step 3: Implement UI based only on real emitted states**
- [ ] **Step 4: Run all Portrait Lab widget tests**
- [ ] **Step 5: Commit**

---

### Task 8: Build, verify and publish the R11 APK

**Files:**
- Modify: `.github/workflows/portrait-mvp.yml`

**Interfaces:**
- Artifact: `Local-Portrait-Lab_R11_QNN_ID_LOCK_debug`

- [ ] **Step 1: Add R11 CI gates**

CI must run:

```bash
flutter test test/portrait_lab
flutter build apk --debug --target lib/portrait_lab_entry.dart --build-name=0.11.0-r11 --build-number=12
```

and verify:
- QNN native core is bundled;
- ONNX Runtime native library is bundled;
- no `.onnx` identity model weight is bundled;
- identity source/channel exists;
- artifact SHA-256 is emitted.

- [ ] **Step 2: Run the complete GitHub Actions workflow**

Expected: all steps success.

- [ ] **Step 3: Inspect workflow logs and artifact list**

Do not claim success from a partial test result.

- [ ] **Step 4: Download and extract the APK artifact**

Place final APK at `/mnt/data/Local-Portrait-Lab_R11_QNN_ID_LOCK_debug.apk`.

- [ ] **Step 5: Hand off the APK and hash**

The user should receive the direct sandbox APK link, build commit, artifact name and SHA-256.