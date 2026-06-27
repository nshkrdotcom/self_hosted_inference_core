# Crucible Runtime

`SelfHostedInferenceCore.CrucibleRuntime` supervises provider-backed Crucible
workers under `SelfHostedInferenceCore.CrucibleRuntimeSupervisor`.

Workers register under `{SelfHostedInferenceCore.CrucibleRuntime, id}` in the
existing process registry, which keeps Crucible runtime ids separate from
service instance ids and adapter registry keys.

At startup a worker resolves its configured provider module and calls the
provider lifecycle. The core runtime never loads model assets directly; concrete
providers own model loading, preflight, signal extraction, trace writing, and
generation.

Offline tests and examples use
`SelfHostedInferenceCore.CrucibleRuntime.FixtureProvider`. Live Bumblebee model
execution is implemented outside the kernel by
`SelfHostedInferenceBumblebee.CrucibleProvider`.

Provider modules may use either the local
`SelfHostedInferenceCore.CrucibleRuntime.Provider` behaviour or the shared
`Crucible.Provider` ABI from `crucible_provider_contracts`. Formal
`Crucible.Provider` modules are wrapped by
`SelfHostedInferenceCore.CrucibleRuntime.FormalProviderAdapter`, which compiles
tap plans before execution and carries canonical capability reports into emitted
forward traces. Required unsupported taps fail closed before provider forward
execution; optional unsupported taps may degrade with capability evidence.

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
