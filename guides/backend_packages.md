# Backend Packages

## Purpose

`self_hosted_inference_core` is intentionally generic.
Concrete backend packages are where service-specific truth should live.

## First Concrete Backend

The first concrete backend package is `llama_cpp_sdk`.
The first built-in attach adapter is `SelfHostedInferenceCore.Ollama`.

It proves the intended split:

- `execution_plane` owns process placement and raw process/session facts
- `self_hosted_inference_core` owns runtime lifecycle and endpoint contracts
- `llama_cpp_sdk` owns `llama-server` boot flags, probes, and stop semantics
- the built-in `ollama` adapter keeps externally managed attach semantics in
  the kernel until a separate package is justified

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
- durable lease lineage above the service-runtime seam

Attach adapters that stay inside `self_hosted_inference_core` should follow
the same ownership rules. They can own backend-specific readiness and health
interpretation, but they still must not claim daemon ownership or drift into
client execution.

## Integration Shape

Backend packages integrate by implementing `SelfHostedInferenceCore.Backend`
and registering with the kernel.

That lets the kernel stay reusable when the second backend arrives while
keeping provider-specific service behavior localized.
