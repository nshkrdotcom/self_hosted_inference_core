# Crucible Runtime

`SelfHostedInferenceCore.CrucibleRuntime` supervises Bumblebee-backed Crucible
workers under `SelfHostedInferenceCore.CrucibleRuntimeSupervisor`.

Workers register under `{SelfHostedInferenceCore.CrucibleRuntime, id}` in the
existing process registry, which avoids collisions with legacy `{:instance,
id}` and adapter registry keys.

At startup a worker resolves its `ModelSurface`, runs surface preflight through
`crucible_bumblebee`, negotiates the canonical serving tap plan, and compiles
one forward serving. Per-request tap changes should remain post-processing
filters unless the configured surface advertises dynamic hooks.

The public API includes:

- `start_child/1`
- `capabilities/1`
- `ready?/1`
- `lease/2`
- `release/1`
- `forward/4`
- `generate/4`

Lease acquire and release emit the existing telemetry event names:

- `[:self_hosted_inference_core, :lease, :acquire]`
- `[:self_hosted_inference_core, :lease, :release]`

`SelfHostedInferenceCore.Health.report/0` includes a `:crucible_runtimes`
section, and `SelfHostedInferenceCore.Readiness.ready?/0` requires at least one
ready Crucible runtime when any are running.
