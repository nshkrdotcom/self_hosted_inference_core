# Architecture

## Role In The Stack

`self_hosted_inference_core` is the runtime kernel for self-hosted inference
services. It sits between the raw placement substrate and backend-specific
service adapters.

```text
external_runtime_transport
  -> self_hosted_inference_core
  -> backend package or attach adapter
  -> jido_integration / req_llm consumers
```

The kernel is intentionally narrow:

- it owns service lifecycle state
- it publishes endpoint-shaped runtime outputs
- it rejects startup plans that contradict service-runtime ownership
- it does not parse inference wire protocols
- it does not own control-plane durability

## Ownership Boundaries

### `external_runtime_transport`

Transport ownership stays below the kernel:

- local, SSH, and guest placement
- subprocess start and attach mechanics
- stdout and stderr delivery
- interrupt and shutdown behavior
- raw exit observation

### `self_hosted_inference_core`

Kernel ownership stays above the transport seam:

- backend registry
- instance identity and reuse
- startup-kind semantics
- readiness orchestration
- health polling and interpretation
- lease tracking
- endpoint publication
- compatibility calculation

### Concrete backend packages

Backend-specific packages or adapters own:

- boot-spec normalization
- backend flags and command rendering
- readiness probes
- health checks
- stop strategy
- backend manifest details

## Control Loop

The kernel follows one service-oriented loop for both startup kinds:

1. Resolve the backend module from the backend registry.
2. Build a `StartupPlan` from an `InstanceSpec`.
3. Validate that the requested startup kind, manifest, management mode,
   execution surface, and transport ownership agree.
4. Ensure or reuse a runtime instance keyed by the backend-provided instance
   identity.
5. Drive readiness until the backend reports an executable endpoint.
6. Publish an `EndpointDescriptor`.
7. Track health and lease activity for as long as the instance remains alive.

## Northbound Contracts

The kernel exposes four primary outputs to higher layers:

- `BackendManifest`
- `CompatibilityResult`
- `EndpointDescriptor`
- `LeaseRef`

`jido_integration` or another control-plane layer can resolve one of these
endpoints and then hand the endpoint-shaped inputs to `req_llm`.

## Why The Kernel Is Separate

Self-hosted inference is a service-runtime problem, not a CLI-session problem
and not a provider-client problem.

Keeping the kernel separate prevents two common architecture failures:

- transport logic leaking upward into backend or control-plane code
- client/request logic leaking downward into service lifecycle code
