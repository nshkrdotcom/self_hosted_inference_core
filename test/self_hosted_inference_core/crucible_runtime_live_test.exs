defmodule SelfHostedInferenceCore.CrucibleRuntimeLiveTest do
  use ExUnit.Case, async: false

  @moduletag :live_cpu_heavy

  alias SelfHostedInferenceCore.CrucibleRuntime

  test "live crucible runtime loads, leases, forwards, and releases" do
    assert System.get_env("CRUCIBLE_LIVE_MODEL") in ["1", "true"]

    id = :"crucible-runtime-live-#{System.unique_integer([:positive])}"

    assert {:ok, pid} = CrucibleRuntime.start_child(id: id, live_model?: true)
    assert CrucibleRuntime.ready?(pid)

    assert {:ok, lease} = CrucibleRuntime.lease(pid, owner_ref: "live-test")

    assert {:ok, %Crucible.ForwardTrace{} = trace} =
             CrucibleRuntime.forward(pid, nil, %{prompt: "Hi"})

    assert :ok = CrucibleRuntime.release(lease)

    assert trace.model_id == "hf-internal-testing/tiny-random-gpt2"
    assert Enum.any?(trace.signals, &(&1.signal_type == :final_logits))

    snapshot = CrucibleRuntime.snapshot(pid)
    assert snapshot.ready?
    assert snapshot.tokenizer_loaded?
    assert snapshot.model_loaded?
    assert snapshot.last_forward_ok?
    assert %Crucible.CapabilityReport{} = snapshot.capabilities
  end
end
