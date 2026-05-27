alias SelfHostedInferenceCore.CrucibleRuntime

id = :"crucible-runtime-example-#{System.unique_integer([:positive])}"

{:ok, pid} =
  CrucibleRuntime.start_child(
    id: id,
    model_ref: "model:fixture"
  )

{:ok, lease} = CrucibleRuntime.lease(pid, owner_ref: "example")
{:ok, trace} = CrucibleRuntime.forward(pid, nil, %{prompt: "hello"})
:ok = CrucibleRuntime.release(lease)

IO.inspect(%{
  ok: true,
  example: "crucible_runtime_mock",
  runtime: id,
  signal_count: length(trace.signal_records),
  ready?: CrucibleRuntime.ready?(pid)
})
