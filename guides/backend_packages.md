# Backend Packages

## Purpose

`self_hosted_inference_core` is intentionally generic.
Concrete backend packages are where service-specific truth should live.

## First Concrete Backend

The first concrete backend package is `llama_cpp_ex`.

It proves the intended split:

- `external_runtime_transport` owns process placement
- `self_hosted_inference_core` owns runtime lifecycle and endpoint contracts
- `llama_cpp_ex` owns `llama-server` boot flags, probes, and stop semantics

## What A Backend Package Should Own

Backend packages should own:

- normalized boot inputs
- provider-specific launch rendering
- readiness interpretation
- health interpretation
- stop strategy
- backend manifest details

The kernel enforces the declared `supported_surfaces`, so backend manifests
need to stay honest about where the runtime can actually execute.

Backend packages should not own:

- transport internals
- client payload parsing
- control-plane durability

## Integration Shape

Backend packages integrate by implementing `SelfHostedInferenceCore.Backend`
and registering with the kernel.

That lets the kernel stay reusable when the second backend arrives while
keeping provider-specific service behavior localized.
