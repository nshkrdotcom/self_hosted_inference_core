<p align="center">
  <img src="assets/self_hosted_inference_core.svg" width="200" alt="self_hosted_inference_core logo" />
</p>

<p align="center">
  <a href="https://github.com/nshkrdotcom/self_hosted_inference_core/blob/master/LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-0F172A.svg" alt="License: MIT" />
  </a>
  <img src="https://img.shields.io/badge/elixir-%7E%3E%201.18-4E2A8E.svg" alt="Elixir ~&gt; 1.18" />
  <a href="https://hexdocs.pm/self_hosted_inference_core">
    <img src="https://img.shields.io/badge/docs-HexDocs-2563EB.svg" alt="HexDocs" />
  </a>
</p>

# self_hosted_inference_core

`self_hosted_inference_core` is the foundational Elixir package for building
private inference integrations with a clear boundary between provider adapters,
transport mechanics, and operational policy. It is intended for environments
where model execution stays under your control across local, edge, and
dedicated infrastructure.

## Scope

- Define stable primitives for self-hosted inference clients and adapters.
- Keep transport and provider concerns separated from application logic.
- Support operationally mature deployments that need auditability and control.

## Installation

Add `self_hosted_inference_core` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:self_hosted_inference_core, "~> 0.1.0"}
  ]
end
```

## Documentation

HexDocs navigation includes the README, changelog, and license as top-level
project pages once docs are generated and published.

## License

Released under the MIT License. See `LICENSE`.
