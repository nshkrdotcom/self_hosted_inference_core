# Repository Guidelines

## Project Structure
- `lib/` contains public `SelfHostedInferenceCore` modules and service-runtime contracts.
- `test/` contains ExUnit coverage.
- `guides/`, `examples/`, `README.md`, and `CHANGELOG.md` must stay aligned with runtime and dependency behavior.
- `doc/` is generated output and should not be edited.

## Execution Plane Stack
- This repo owns service-runtime semantics above `execution_plane`; do not expose raw process runtime mechanics as the public API.
- Keep committed `execution_plane` dependency tuples as ordinary Hex
  requirements. Managed development loads the MWO bootstrap and gets eligible
  local/GitHub/Hex coordinates from Portfolio Registry.
- Local sibling development uses `../execution_plane/core/execution_plane` for
  `:execution_plane` and `../execution_plane/runtimes/execution_plane_process`
  for the process lane. Do not point `:execution_plane` at the sibling repo
  root; that root is the non-published Blitz workspace project.
- `llama_cpp_sdk` is the active proof backend for this layer.

## Dependency Sources And Runtime Env
- Operator source preferences live outside this repository. MWO's
  process-scoped bootstrap pointer is the only dependency-management
  environment input read by `mix.exs`; publish mode remains Hex-only.
- This repo is not in the discovered Weld consumer set. Do not add a Weld
  dependency during this Phase 2 cleanup pass.
- Runtime application code under `lib/**` must not call direct OS env APIs such
  as `System.get_env`, `System.fetch_env`, `System.put_env`, or
  `System.delete_env`.
- Runtime/deployment env reads belong in `config/runtime.exs` or an explicit
  `Config.Provider`. Library code receives explicit options, application
  config, credential providers, or caller-supplied env maps from the top-level
  application.

## Gates
- Run `mix format`.
- Run `mix compile --warnings-as-errors`.
- Run `mix test`.
- Run `mix credo --strict`.
- Run `mix dialyzer`.
- Run `mix docs --warnings-as-errors`.
