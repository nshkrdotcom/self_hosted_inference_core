# Real Model Live Gates

Purpose: run the V5 supervised native Bumblebee runtime gates.

## What this covers

The live Crucible runtime starts a worker with `live_model?: true`, loads the
requested Bumblebee model, compiles the canonical tap plan, blocks readiness
until that setup finishes, leases the worker, runs a forward pass from the
already-loaded bundle, writes a trace, optionally runs one-step generation for
causal models, and releases the lease.

## Quickstart

```bash
CRUCIBLE_LIVE_MODEL=true mix test --only live_cpu_heavy
CRUCIBLE_LIVE_MODEL=true CRUCIBLE_BUMBLEBEE_MODEL_ID=gpt2 mix test --only live_cpu_heavy
CRUCIBLE_LIVE_MODEL=true mix run examples/crucible_runtime_ladder_live.exs -- --backend binary
```

Programmatic startup:

```elixir
{:ok, pid} = SelfHostedInferenceCore.CrucibleRuntime.start_child(id: :live, live_model?: true)
{:ok, lease} = SelfHostedInferenceCore.CrucibleRuntime.lease(pid)
{:ok, trace} = SelfHostedInferenceCore.CrucibleRuntime.forward(pid, nil, %{prompt: "Hi"})
:ok = SelfHostedInferenceCore.CrucibleRuntime.release(lease)
```

## Related guides

- [Crucible Runtime](crucible_runtime.md)
- [Runtime Registry](runtime_registry.md)
