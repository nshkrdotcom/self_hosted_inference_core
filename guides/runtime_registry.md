# Runtime Registry

## Purpose

The runtime registry is responsible for mapping a backend-specific instance key
to exactly one managed runtime instance within the BEAM.

That registry is what makes honest reuse possible.

## Instance Identity

Every backend returns a `StartupPlan` with an `instance_key`.

That key should include the backend inputs that materially change runtime
behavior, for example:

- backend identity
- model identity
- attach target
- placement-relevant execution surface details
- launch knobs that affect compatibility or reuse

If two requests resolve to the same `instance_key`, they target the same
runtime instance.

## Ensure Versus Reuse

`SelfHostedInferenceCore.ensure_instance/2` does two things:

1. creates a new runtime when no matching instance exists
2. reuses the existing runtime when the instance key already exists

That lets higher layers ask for a compatible runtime repeatedly without
re-implementing deduplication or readiness bookkeeping.

## Lease Semantics

Leases are explicit.

When a consumer resolves an endpoint through `resolve_endpoint/3`, the kernel:

1. ensures or reuses the instance
2. creates a `LeaseRef`
3. returns the published endpoint with `lease_ref` populated

Leases are tracked per instance and support:

- `owner_ref`
- optional `ttl_ms`
- explicit release
- idempotent release after instance shutdown

## Endpoint Publication

The registry does not publish an endpoint until readiness succeeds.

Once a runtime is ready, `publish_endpoint/1` returns the current
`EndpointDescriptor` without a lease attached. Lease acquisition produces a
lease-scoped copy of that same descriptor.

## Health Tracking

Runtime processes continue to poll backend-defined health checks after
readiness succeeds.

The registry snapshot exposes:

- lifecycle status
- health status
- active lease count
- published endpoint

This lets higher layers inspect current runtime truth without owning daemon
state directly.
