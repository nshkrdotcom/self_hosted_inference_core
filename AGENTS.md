# Repository Guidelines

## Project Structure
- `lib/` contains public `SelfHostedInferenceCore` modules and service-runtime contracts.
- `test/` contains ExUnit coverage.
- `guides/`, `examples/`, `README.md`, and `CHANGELOG.md` must stay aligned with runtime and dependency behavior.
- `doc/` is generated output and should not be edited.

## Execution Plane Stack
- This repo owns service-runtime semantics above `execution_plane`; do not expose raw process runtime mechanics as the public API.
- Keep `execution_plane` dependency resolution publish-aware: local path deps for sibling development, Hex constraints for release builds.
- `llama_cpp_sdk` is the active proof backend for this layer.

## Gates
- Run `mix format`.
- Run `mix compile --warnings-as-errors`.
- Run `mix test`.
- Run `mix credo --strict`.
- Run `mix dialyzer`.
- Run `mix docs --warnings-as-errors`.
