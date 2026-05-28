# Real Model Live Gates

Purpose: run supervised native model runtime gates through an explicit provider.

## What this covers

The live Crucible runtime starts a worker with a configured provider module.
The provider loads the requested model, compiles or selects its tap plan, blocks
readiness until setup finishes, runs forward from the already-loaded bundle,
writes a trace, optionally runs one-step generation for causal models, and
releases the lease.

## Quickstart

```bash
CRUCIBLE_LIVE_MODEL=true mix run examples/crucible_runtime_live.exs -- \
  --provider-module SelfHostedInferenceBumblebee.CrucibleProvider \
  --model hf-internal-testing/tiny-random-gpt2 \
  --backend binary
```

Programmatic startup:

```elixir
{:ok, pid} =
  SelfHostedInferenceCore.CrucibleRuntime.start_child(
    id: :live,
    provider_module: SelfHostedInferenceBumblebee.CrucibleProvider,
    provider_opts: [model_id: "hf-internal-testing/tiny-random-gpt2", backend: :binary]
  )
{:ok, lease} = SelfHostedInferenceCore.CrucibleRuntime.lease(pid)
{:ok, trace} = SelfHostedInferenceCore.CrucibleRuntime.forward(pid, nil, %{prompt: "Hi"})
:ok = SelfHostedInferenceCore.CrucibleRuntime.release(lease)
```

## Related guides

- [Crucible Runtime](crucible_runtime.md)
- [Runtime Registry](runtime_registry.md)
