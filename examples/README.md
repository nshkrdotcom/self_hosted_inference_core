# Examples

## Lease Reuse Demo

`lease_reuse_demo.exs` starts a small file-backed demo service runtime through
the kernel, resolves two endpoints against the same backend/model, and shows
that:

- the runtime instance is reused
- each caller receives its own lease
- the published endpoint stays stable across lease reuse

Run it with:

```bash
mix run examples/lease_reuse_demo.exs
```

The example does not depend on a real model binary. It uses a long-lived
subprocess fixture so the service-runtime and lease behavior remain honest.
