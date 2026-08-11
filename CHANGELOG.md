# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog and this project adheres to Semantic
Versioning.

## [Unreleased]

## [0.2.0] - 2026-08-10

- Add the V4 live native Bumblebee runtime path with truthful readiness after
  tokenizer/model/backend/preflight/tap-plan setup and live CPU-heavy gate
  coverage.
- Add the V5 hosted runtime ladder for tiny GPT-2 and standard GPT-2, including
  readiness rejection on preflight failure, lease/forward/generation/release
  coverage, health capability reports, and `tmp/crucible_v5` transcripts.
- Bump the package to `0.2.0` for the Crucible runtime integration.
- Add supervised `SelfHostedInferenceCore.CrucibleRuntime` workers with
  lease, readiness, health, forward, and generation APIs over Crucible
  Bumblebee runners.
- Add governed self-hosted endpoint authority materialization for target
  preferences and Ollama attach specs, with direct unmanaged auth/config/attach
  field rejection and raw-header-free attach instance keys.
- Make the published package resolve Execution Plane dependencies from Hex
  when checkout-only build support is absent, while retaining deterministic
  sibling paths for workspace development.

## [0.1.0] - 2026-04-06

- Initial Release
