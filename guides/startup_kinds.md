# Startup Kinds

## Why Startup Kind Matters

Self-hosted runtimes do not all have the same lifecycle shape.

Some are spawned and supervised by the BEAM.
Others already exist and need to be attached, observed, and published
honestly.

`self_hosted_inference_core` makes that distinction explicit through
`startup_kind`.

## `:spawned`

Use `:spawned` when the BEAM owns the service process.

Characteristics:

- runtime process is started through `external_runtime_transport`
- stdout and stderr can participate in readiness interpretation
- transport exit is part of lifecycle truth
- `management_mode` resolves to `:jido_managed`
- the startup plan must include a transport-owned process surface

Good fits:

- `llama.cpp` style local servers
- process-owned `vllm` deployments
- any backend where the runtime kernel is expected to start and stop the
  service directly

## `:attach_existing_service`

Use `:attach_existing_service` when the daemon already exists outside the BEAM.

Characteristics:

- no spawned subprocess is required
- readiness is attach-oriented, not launch-oriented
- health is interpreted without claiming daemon ownership
- `management_mode` resolves to `:externally_managed`

Good fits:

- `ollama`
- externally managed `vllm`
- service managers that publish an endpoint before the Elixir runtime arrives

## Kernel Invariants

The kernel rejects startup plans that break the ownership boundary. In
practice that means:

- requested `startup_kind` must match the backend-produced startup plan
- manifest `startup_kind` and runtime `management_mode` must agree with the
  plan
- `:spawned` plans must carry a transport because the BEAM is claiming process
  ownership

## Shared Output Surface

Both startup kinds converge on the same published contracts:

- `EndpointDescriptor`
- `LeaseRef`
- `CompatibilityResult`

That keeps higher-level consumers consistent while preserving truthful runtime
ownership underneath.

See [`examples/README.md`](../examples/README.md) for runnable demos of both
startup kinds.
