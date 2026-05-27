# Real Model Live Gates

Purpose: run the V4 supervised native Bumblebee runtime gate.

## What this covers

The live Crucible runtime starts a worker with `live_model?: true`, loads
tiny GPT-2, compiles the canonical tap plan, blocks readiness until that setup
finishes, leases the worker, runs a forward pass, writes a v4 trace, and
releases the lease.

## Quickstart

```bash
CRUCIBLE_LIVE_MODEL=true mix test --only live_cpu_heavy
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
