# Examples

## `:spawned` Lease Reuse Demo

`lease_reuse_demo.exs` starts a small file-backed demo service runtime through
the kernel, calls `ensure_endpoint/4` twice against the same backend/model, and
shows that:

- the runtime instance is reused
- each caller receives a fresh published lease ref
- the published endpoint stays stable across lease reuse

Run it with:

```bash
mix run examples/lease_reuse_demo.exs
```

The example mirrors the northbound request shape used by `jido_integration`.
It does not depend on a real model binary. It uses a long-lived subprocess
fixture so the service-runtime and lease behavior remain honest.

For the first concrete backend package, see the spawned endpoint publication
demo in `llama_cpp_ex/examples/spawned_endpoint_demo.exs`.

## `:attach_existing_service` Demo

`attach_existing_service_demo.exs` attaches to a real externally managed
Ollama daemon through `SelfHostedInferenceCore.Ollama` and shows that:

- the runtime instance is resolved as `:externally_managed`
- endpoint and lease contracts stay the same as the spawned path
- stopping the kernel instance only drops the kernel-owned lease path
- the attached local endpoint can be resolved again without moving ownership
  into the BEAM

Run it with:

```bash
OLLAMA_MODEL=llama3.2 \
mix run examples/attach_existing_service_demo.exs
```

Optional environment variables:

- `OLLAMA_ROOT_URL`
  - defaults to `http://127.0.0.1:11434` or the configured
    `:ollama_root_url` application setting
- `OLLAMA_MODEL`
  - defaults to `llama3.2`

## Crucible Runtime Mock Demo

`crucible_runtime_mock.exs` starts a supervised Crucible runtime with fixture
model outputs, acquires a lease, runs a forward pass, and releases the lease.

Run it with:

```bash
mix run examples/crucible_runtime_mock.exs
```

## Crucible Runtime Live Demo

`crucible_runtime_live.exs` skips cleanly unless live model execution is
enabled.

```bash
CRUCIBLE_LIVE_MODEL=1 mix run examples/crucible_runtime_live.exs
```

## Crucible Runtime Live Ladder

`crucible_runtime_ladder_live.exs` runs a hosted runtime ladder through an
explicit provider module. It loads each model in a supervised runtime, checks
readiness, acquires a lease, runs hosted forward, attempts one-step generation,
releases the lease, and writes hosted matrix artifacts.

```bash
CRUCIBLE_LIVE_MODEL=1 mix run examples/crucible_runtime_ladder_live.exs -- \
  --provider-module SelfHostedInferenceBumblebee.CrucibleProvider \
  --models hf-internal-testing/tiny-random-gpt2 \
  --backend binary
```
