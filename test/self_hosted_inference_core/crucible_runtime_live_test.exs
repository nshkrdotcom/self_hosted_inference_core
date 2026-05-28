defmodule SelfHostedInferenceCore.CrucibleRuntimeLiveTest do
  use ExUnit.Case, async: false

  @moduletag :live_cpu_heavy

  alias SelfHostedInferenceCore.{CrucibleRuntime, Health}

  @tag timeout: 600_000
  test "live crucible runtime loads, leases, forwards, and releases" do
    assert System.get_env("CRUCIBLE_LIVE_MODEL") in ["1", "true"]

    id = :"crucible-runtime-live-#{System.unique_integer([:positive])}"

    model_id =
      System.get_env("CRUCIBLE_BUMBLEBEE_MODEL_ID") || "hf-internal-testing/tiny-random-gpt2"

    assert {:ok, pid} = CrucibleRuntime.start_child(id: id, live_model?: true)
    assert CrucibleRuntime.ready?(pid)

    assert {:ok, lease} = CrucibleRuntime.lease(pid, owner_ref: "live-test")

    assert {:ok, %Crucible.ForwardTrace{} = trace} =
             CrucibleRuntime.forward(pid, nil, %{prompt: "Hi"}, timeout: 240_000)

    generation = CrucibleRuntime.generate(pid, nil, "Hi", max_new_tokens: 1, timeout: 240_000)

    assert :ok = CrucibleRuntime.release(lease)

    assert trace.model_id == model_id
    assert Enum.any?(trace.signals, &(&1.signal_type == :final_logits))

    if model_id =~ "gpt2" or model_id =~ "Qwen" do
      assert {:ok, %{success_level: :generation_step_logits, step_count: 1}} = generation
    else
      assert {:error, _reason} = generation
    end

    snapshot = CrucibleRuntime.snapshot(pid)
    assert snapshot.ready?
    assert snapshot.tokenizer_loaded?
    assert snapshot.model_loaded?
    assert snapshot.last_forward_ok?
    assert %Crucible.CapabilityReport{} = snapshot.capabilities

    assert %{crucible_runtimes: health_snapshots} = Health.report()
    assert health_snapshot = Enum.find(health_snapshots, &(&1.id == id))
    assert health_snapshot.ready?
    assert health_snapshot.model_id == model_id
    assert %Crucible.CapabilityReport{} = health_snapshot.capabilities
  end
end
