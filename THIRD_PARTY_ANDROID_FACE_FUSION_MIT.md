# Android Face Identity Components Notice

Portrait Lab R11 adapts source code from `Parasaran-Python/android-face-fusion` at pinned commit `f38a70e4bacaab4132538421c471f9d4d3ccac00` for on-device SCRFD face detection, ArcFace embedding, INSwapper inference and face blending.

The referenced source repository is MIT licensed. Portrait Lab vendors only the required Java source during reproducible builds and does not commit or bundle its face-model binaries.

Runtime model pack:

- `det_10g.onnx` — SCRFD face detector
- `w600k_r50.onnx` — ArcFace identity encoder
- `inswapper_128.onnx` — INSwapper identity transfer model
- `emap.bin` — learned INSwapper embedding transform

These runtime model assets are downloaded into Android app-private storage on first identity-locked generation and SHA-256 verified before use. They are intended here for research/evaluation. This repository does not grant commercial rights to third-party model weights or training data. Production/commercial use requires independent license review of the selected model assets.
