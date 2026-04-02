<p align="center">
  <img src="assets/self_hosted_inference_core.svg" width="200" alt="self_hosted_inference_core logo" />
</p>

<p align="center">
  <a href="https://hex.pm/packages/self_hosted_inference_core">
    <img src="https://img.shields.io/badge/hex-self__hosted__inference__core-8B5CF6.svg" alt="Hex package" />
  </a>
  <a href="https://hexdocs.pm/self_hosted_inference_core">
    <img src="https://img.shields.io/badge/docs-HexDocs-2563EB.svg" alt="HexDocs" />
  </a>
  <a href="./LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-111111.svg" alt="MIT License" />
  </a>
</p>

# SelfHostedInferenceCore

`self_hosted_inference_core` is the service-runtime kernel for local and
self-hosted inference backends.

It owns the runtime concerns that sit between raw process placement and
backend-specific boot logic:

- backend registration
- runtime instance registration
- startup-kind handling
- readiness orchestration
- health monitoring
- lease and reuse semantics
- endpoint publication
- backend-to-consumer compatibility calculation

It does **not** own transport mechanics or client protocol execution.
`external_runtime_transport` owns process placement and IO lifecycle.
`req_llm` remains the data-plane client after an endpoint has been resolved.

## Runtime Stack

```text
external_runtime_transport
  -> self_hosted_inference_core
  -> concrete backend package or attach adapter
  -> req_llm consumers through EndpointDescriptor
```

That split keeps service lifecycle in the runtime stack and keeps request
execution in the client layer.

## Startup Kinds

`self_hosted_inference_core` treats startup topology as an explicit part of the
contract:

- `:spawned`
  - BEAM-managed service lifecycle
  - maps to `management_mode: :jido_managed`
- `:attach_existing_service`
  - externally managed daemon lifecycle
  - maps to `management_mode: :externally_managed`

Both paths use the same northbound endpoint and lease contracts.
The kernel validates that backends keep startup kind, management mode, and
transport ownership truthful.

## Installation

Add the package to your dependency list:

```elixir
def deps do
  [
    {:self_hosted_inference_core, "~> 0.1.0"}
  ]
end
```

Concrete backends register themselves against the kernel by implementing
`SelfHostedInferenceCore.Backend`.

## Quick Start

Define a backend or attach adapter, register it, and resolve an endpoint:

```elixir
alias SelfHostedInferenceCore.{ConsumerManifest, InstanceSpec}

:ok = SelfHostedInferenceCore.register_backend(MyBackend)

consumer =
  ConsumerManifest.new!(
    consumer: :jido_integration_req_llm,
    accepted_runtime_kinds: [:service],
    accepted_management_modes: [:jido_managed, :externally_managed],
    accepted_protocols: [:openai_chat_completions],
    required_capabilities: %{streaming?: true},
    optional_capabilities: %{},
    constraints: %{},
    metadata: %{}
  )

spec =
  InstanceSpec.new!(
    backend: :my_backend,
    backend_options: %{model_identity: "demo-model"}
  )

{:ok, resolution} =
  SelfHostedInferenceCore.resolve_endpoint(
    spec,
    consumer,
    owner_ref: "run-123",
    ttl_ms: 30_000
  )

resolution.endpoint.base_url
resolution.lease.lease_ref
```

See [`examples/README.md`](examples/README.md) for runnable demos covering both
`:spawned` and `:attach_existing_service`.

## HexDocs

HexDocs includes:

- architecture and stack-boundary guidance
- runtime registry and lease semantics
- startup-kind guidance for spawned and attached services
- runnable examples

## License

Released under the MIT License. See `LICENSE`.
