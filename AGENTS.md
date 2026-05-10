# Repository Guidelines

## Project Structure
- `lib/` contains public `SelfHostedInferenceCore` modules and service-runtime contracts.
- `test/` contains ExUnit coverage.
- `guides/`, `examples/`, `README.md`, and `CHANGELOG.md` must stay aligned with runtime and dependency behavior.
- `doc/` is generated output and should not be edited.

## Execution Plane Stack
- This repo owns service-runtime semantics above `execution_plane`; do not expose raw process runtime mechanics as the public API.
- Keep `execution_plane` dependency resolution publish-aware through
  `build_support/dependency_sources.exs` and
  `build_support/dependency_sources.config.exs`: local path deps for sibling
  development, GitHub fallback when needed, and Hex constraints for release
  builds.
- Local sibling development uses `../execution_plane/core/execution_plane` for
  `:execution_plane` and `../execution_plane/runtimes/execution_plane_process`
  for the process lane. Do not point `:execution_plane` at the sibling repo
  root; that root is the non-published Blitz workspace project.
- `llama_cpp_sdk` is the active proof backend for this layer.

## Dependency Sources And Runtime Env
- Use `.dependency_sources.local.exs` for local dependency-source overrides; it
  is gitignored and must not be committed.
- Dependency source selection must not read OS environment variables.
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
