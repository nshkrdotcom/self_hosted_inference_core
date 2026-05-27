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
`execution_plane` owns process placement, IO lifecycle, and raw process facts.
`req_llm` remains the data-plane client after an endpoint has been resolved.

## Runtime Stack

```text
execution_plane
  -> self_hosted_inference_core
  -> concrete backend package or attach adapter
  -> req_llm consumers through EndpointDescriptor
```

That split keeps service lifecycle in the runtime stack and keeps request
execution in the client layer.

## Backends

Two backend shapes are now proved:

- built-in attach adapter: `SelfHostedInferenceCore.Ollama`
- concrete spawned backend package: `llama_cpp_sdk`
- built-in service-mode simulation backend:
  `SelfHostedInferenceCore.Simulation`
- supervised Crucible runtime workers:
  `SelfHostedInferenceCore.CrucibleRuntime`

`SelfHostedInferenceCore.Ollama` proves the first truthful
`management_mode: :externally_managed` path.
It attaches to an already running Ollama daemon, owns readiness and health
interpretation above the transport seam, and publishes the same northbound
endpoint contract used by the spawned path.

`llama_cpp_sdk` plugs into the kernel by implementing
`SelfHostedInferenceCore.Backend` and owns:

- `llama-server` boot-spec normalization
- readiness and health probes
- stop semantics for a spawned service
- backend manifest publication
- endpoint descriptor production

That keeps the kernel generic while proving both ownership shapes on real
backends.

`SelfHostedInferenceCore.Simulation` is the built-in PRELIM service-mode
simulation backend. It is selected by application configuration and a backend
manifest, uses Execution Plane's `:lower_simulation` process transport, and
publishes normal endpoint, readiness, health, and lease contracts without
launching a real backend process. It is not selected through a public
`simulation:` request option.

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
substrate ownership truthful. It also rejects execution surfaces that are not
declared in the backend manifest.

## Governed Authority

Standalone self-hosted inference keeps the existing local ergonomics:
`Ollama.AttachSpec` accepts direct endpoint config and endpoint auth. When no
root URL is supplied, the attach default comes from
`config :self_hosted_inference_core, :ollama_root_url, ...`, falling back to
`http://127.0.0.1:11434`.

Governed self-hosted inference is selected with
`governed_authority: %SelfHostedInferenceCore.GovernedAuthority{}` or
equivalent attrs. In that mode the kernel and built-in Ollama attach adapter
materialize endpoint identity, service identity, target posture, attach grant,
credential refs, endpoint auth, backend options, execution surface, and
redaction refs only from the authority packet.

When `governed_authority` is present, direct target-preference fields such as
`backend`, `startup_kind`, `execution_surface`, `backend_options`,
`boot_spec`, `attach_spec`, `metadata`, `root_url`, `api_key`, and `headers`
are rejected. Direct Ollama attach fields such as `root_url`, `base_url`,
`model_identity`, `api_key`, `headers`, `ollama_http`, `execution_surface`,
and `metadata` are also rejected. Authority refs are copied into metadata, but
materialized endpoint tokens are not copied into metadata, lease metadata, or
instance ids.

## Installation

Add the package to your dependency list:

```elixir
def deps do
  [
    {:self_hosted_inference_core, "~> 0.2.0"}
  ]
end
```

Concrete backends register themselves against the kernel by implementing
`SelfHostedInferenceCore.Backend`.

`self_hosted_inference_core` stays the service-runtime family kit. It consumes
Execution Plane process facts for spawned services but keeps readiness, health,
lease reuse, and endpoint publication semantics local to this repo.

See [`guides/backend_packages.md`](guides/backend_packages.md) for how the
kernel expects concrete backend packages to attach.
See [`guides/ollama_attach.md`](guides/ollama_attach.md) for the built-in
attached-local backend.
See [`guides/crucible_runtime.md`](guides/crucible_runtime.md) for supervised
Crucible forward/generation workers.

## Quick Start

Define a backend or attach adapter, register it, and ensure a northbound
endpoint for a request:

```elixir
alias SelfHostedInferenceCore.ConsumerManifest

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
    metadata: %{adapter: :req_llm}
  )

request = %{
  request_id: "req-123",
  target_preference: %{
    target_class: "self_hosted_endpoint",
    backend: "my_backend",
    backend_options: %{model_identity: "demo-model"}
  }
}

context = %{
  run_id: "run-123",
  attempt_id: "run-123:1",
  boundary_ref: "boundary-123",
  observability: %{trace_id: "trace-123"}
}

{:ok, endpoint, compatibility} =
  SelfHostedInferenceCore.ensure_endpoint(
    request,
    consumer,
    context,
    owner_ref: "run-123",
    ttl_ms: 30_000
  )

endpoint.base_url
endpoint.lease_ref
compatibility.reason
```

See [`examples/README.md`](examples/README.md) for runnable demos covering both
`:spawned` and `:attach_existing_service`.

## HexDocs

HexDocs includes:

- architecture and stack-boundary guidance
- built-in `ollama` attach guidance
- concrete backend package guidance
- the northbound endpoint contract used by `jido_integration`
- runtime registry, lease reuse, and endpoint publication semantics
- startup-kind guidance for spawned and attached services
- runnable examples

## License

Released under the MIT License. See `LICENSE`.

## V4 Status

Status: `hosted-runtime-gate-passing`.

`SelfHostedInferenceCore.CrucibleRuntime` can start a live native Bumblebee
worker with `live_model?: true`. Readiness is true only after the tokenizer,
model parameters, backend, surface preflight, and tap plan are loaded. The live
gate is:

```bash
CRUCIBLE_LIVE_MODEL=true mix test --only live_cpu_heavy
```
