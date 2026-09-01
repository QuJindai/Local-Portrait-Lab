# Local Portrait Lab

Android 本地 AI 人像实验室：导入本人照片，选择风格，在手机端完成 img2img 生图并保存结果。

## Status

- Product baseline: 6-page Portrait Lab prototype approved
- Development baseline: Local-Diffusion / stable-diffusion.cpp
- Upstream: `rmatif/Local-Diffusion`
- Locked upstream commit: `184b7f92cf2f810e7d5eb4b04b190a5da829005f`
- First target device: Android arm64, S24U gate
- First milestone: photo → style → local img2img → save/history

## Development policy

- Local inference first; no server-side image generation in V1.
- Real progress only; no fake generation percentage.
- Test-first changes on the portrait domain/controller.
- Preserve Apache-2.0 upstream attribution.

## Branches

- `main`: stable baseline
- `feat/portrait-mvp`: active MVP development

## Upstream credits

This project builds on [rmatif/Local-Diffusion](https://github.com/rmatif/Local-Diffusion), powered by [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp).
