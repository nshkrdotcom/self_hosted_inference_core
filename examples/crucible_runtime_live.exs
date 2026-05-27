if System.get_env("CRUCIBLE_LIVE_MODEL") not in ["1", "true"] do
  IO.inspect(%{ok: true, example: "crucible_runtime_live", skipped: true, reason: :live_not_enabled})
  System.halt(0)
end

alias SelfHostedInferenceCore.CrucibleRuntime

id = :"crucible-runtime-live-example-#{System.unique_integer([:positive])}"

{:ok, pid} = CrucibleRuntime.start_child(id: id, live_model?: true)
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
