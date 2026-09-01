# Portrait Lab overlay

Files under `overlay/lib` and `overlay/test` are copied onto the locked Local-Diffusion checkout by `scripts/bootstrap_upstream.sh`.

This keeps upstream traceable while Portrait Lab code remains small and reviewable. Do not place user portrait photos, model weights, generated images, API tokens, or signing secrets in this directory.
