# Ollama Attach

## Purpose

`SelfHostedInferenceCore.Ollama` is the first built-in
`:attach_existing_service` backend.

It exists to prove the `:externally_managed` path for a real local backend
without forcing a separate package too early.

## What It Owns

- normalized attach input through `Ollama.AttachSpec`
- daemon reachability checks through `/api/version`
- model-availability checks through `/api/show`
- warm-versus-cold health interpretation through `/api/ps`
- OpenAI-compatible endpoint publication at `#{root_url}/v1`

It does not own request execution. Once the endpoint is published, callers
should execute through `req_llm`.

## Quick Start

```elixir
alias SelfHostedInferenceCore.ConsumerManifest
alias SelfHostedInferenceCore.Ollama

:ok = Ollama.register_backend()

consumer =
  ConsumerManifest.new!(
    consumer: :jido_integration_req_llm,
    accepted_runtime_kinds: [:service],
    accepted_management_modes: [:externally_managed],
    accepted_protocols: [:openai_chat_completions],
    required_capabilities: %{streaming?: true},
    optional_capabilities: %{tool_calling?: :unknown},
    constraints: %{startup_kind: :attach_existing_service},
    metadata: %{}
  )

{:ok, resolution} =
  Ollama.resolve_endpoint(
    %{
      root_url: "http://127.0.0.1:11434",
      model_identity: "llama3.2"
    },
    consumer,
    owner_ref: "run-123",
    ttl_ms: 30_000
  )

resolution.endpoint.base_url
resolution.endpoint.management_mode
resolution.lease.lease_ref
```

## Readiness

Readiness stays attach-oriented:

1. poll `/api/version` until the daemon is reachable
2. poll `/api/show` until the requested model is available
3. publish the OpenAI-compatible endpoint only after both checks succeed

That keeps the route honest when the daemon is already running but the model is
still being pulled or loaded.

## Health Interpretation

Health stays truthful to attached-service semantics:

- `:healthy`
  - daemon reachable and requested model currently listed in `/api/ps`
- `:degraded`
  - daemon reachable and model is installed, but not currently warm/running
- `:unavailable`
  - daemon unreachable or requested model no longer resolves through `/api/show`

The health result updates on the same runtime snapshot contract used by
spawned services.

## Notes

- `root_url` defaults to `http://127.0.0.1:11434`
- `OLLAMA_HOST` is honored when `root_url` is omitted
- passing a `base_url` that already ends in `/v1` is normalized back to the
  daemon root before publication
- the current manifest stays local-only with `supported_surfaces:
  [:local_subprocess]`
