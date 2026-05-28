if System.get_env("CRUCIBLE_LIVE_MODEL") not in ["1", "true"] do
  IO.inspect(%{ok: true, example: "crucible_runtime_live", skipped: true, reason: :live_not_enabled})
  System.halt(0)
end

alias SelfHostedInferenceCore.CrucibleRuntime

{opts, _rest, _invalid} =
  OptionParser.parse(System.argv(),
    strict: [
      provider_module: :string,
      model: :string,
      backend: :string,
      artifact_root: :string
    ]
  )

provider_module =
  opts
  |> Keyword.get(:provider_module, "SelfHostedInferenceBumblebee.CrucibleProvider")
  |> case do
    "SelfHostedInferenceCore.CrucibleRuntime.FixtureProvider" ->
      SelfHostedInferenceCore.CrucibleRuntime.FixtureProvider

    "SelfHostedInferenceBumblebee.CrucibleProvider" ->
      SelfHostedInferenceBumblebee.CrucibleProvider

    other ->
      {:unsupported_provider_module, other}
  end

unless is_atom(provider_module) and Code.ensure_loaded?(provider_module) do
  IO.inspect(%{
    ok: false,
    example: "crucible_runtime_live",
    reason: {:provider_not_loaded, provider_module}
  })

  System.halt(2)
end

id = :"crucible-runtime-live-example-#{System.unique_integer([:positive])}"

{:ok, pid} =
  CrucibleRuntime.start_child(
    id: id,
    provider_module: provider_module,
    provider_opts: [
      model_id: Keyword.get(opts, :model, "hf-internal-testing/tiny-random-gpt2"),
      backend: Keyword.get(opts, :backend, "binary"),
      artifact_root: Keyword.get(opts, :artifact_root),
      max_new_tokens: 1
    ]
  )

{:ok, lease} = CrucibleRuntime.lease(pid, owner_ref: "example")
{:ok, trace} = CrucibleRuntime.forward(pid, nil, %{prompt: "Hi"})
:ok = CrucibleRuntime.release(lease)

IO.inspect(%{
  ok: true,
  example: "crucible_runtime_live",
  runtime: id,
  ready?: CrucibleRuntime.ready?(pid),
  model_id: trace.model_id,
  signal_count: length(trace.signals),
  trace_id: trace.trace_id
})
