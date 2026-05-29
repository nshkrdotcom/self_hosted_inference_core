defmodule SelfHostedInferenceCore.CrucibleRuntimeTest do
  use ExUnit.Case, async: false

  alias CrucibleTap.TapPlan
  alias SelfHostedInferenceCore.{CrucibleRuntime, Health, LeaseRef, Readiness}

  alias SelfHostedInferenceCore.TestSupport.{
    FailingCrucibleProvider,
    InvalidTraceCrucibleProvider
  }

  setup do
    on_exit(fn ->
      for snapshot <- CrucibleRuntime.list_snapshots() do
        if pid = CrucibleRuntime.whereis(snapshot.id) do
          try do
            DynamicSupervisor.terminate_child(
              SelfHostedInferenceCore.CrucibleRuntimeSupervisor,
              pid
            )
          catch
            :exit, _reason -> :ok
          end
        end
      end
    end)

    :ok
  end

  test "starts worker, leases, forwards, and releases" do
    id = :"crucible-runtime-#{System.unique_integer([:positive])}"
    tap_plan = tap_plan()

    assert {:ok, pid} =
             CrucibleRuntime.start_child(
               id: id,
               model_id: "model:fixture",
               serving_tap_plan: tap_plan,
               predict_fun: &fixture_outputs/1
             )

    assert CrucibleRuntime.whereis(id) == pid
    assert CrucibleRuntime.ready?(pid)
    assert {:ok, capabilities} = CrucibleRuntime.capabilities(pid)
    assert capabilities.surface == :example_transformer

    assert {:ok, %LeaseRef{} = lease} = CrucibleRuntime.lease(pid, owner_ref: "test")
    assert lease.metadata.runtime == id

    assert {:ok, %Crucible.ForwardTrace{} = trace} =
             CrucibleRuntime.forward(pid, tap_plan, %{prompt: "hello"})

    assert trace.model_id == "model:fixture"
    assert trace.final_logits.signal_type == :final_logits
    assert trace.metadata[:tap_plan_id] == "crucible-runtime-test"

    assert :ok = CrucibleRuntime.release(lease)
    assert CrucibleRuntime.snapshot(pid).lease_count == 0
  end

  test "fixture capabilities advertise only what the provider emits" do
    id = :"crucible-runtime-capabilities-#{System.unique_integer([:positive])}"
    assert {:ok, pid} = CrucibleRuntime.start_child(id: id)

    assert {:ok, capabilities} = CrucibleRuntime.capabilities(pid)
    assert capabilities.final_logits == true
    assert capabilities.hidden_states == false
    assert capabilities.attentions == false
    assert capabilities.cache_metadata == false
    assert capabilities.token_boundary_steering == false
  end

  test "generation uses configured custom loop" do
    id = :"crucible-runtime-generation-#{System.unique_integer([:positive])}"
    generation_runner = fn input, plan -> %{input: input, mode: plan.mode} end

    assert {:ok, pid} =
             CrucibleRuntime.start_child(
               id: id,
               generation_runner: generation_runner
             )

    steering = %{trace_id: "trace-1", token_biases: %{1 => 1.0}, mode: :token_boundary}

    assert {:ok, %{input: "prompt", mode: :token_boundary}} =
             CrucibleRuntime.generate(pid, nil, "prompt", steering_plan: steering)
  end

  test "health and readiness include crucible runtimes" do
    id = :"crucible-runtime-health-#{System.unique_integer([:positive])}"
    assert {:ok, _pid} = CrucibleRuntime.start_child(id: id)

    assert Readiness.ready?()
    assert %{crucible_runtimes: [snapshot | _]} = Health.report()
    assert snapshot.ready?
  end

  test "registry key does not collide with service runtime instance keys" do
    id = :"crucible-runtime-registry-#{System.unique_integer([:positive])}"
    assert {:ok, pid} = CrucibleRuntime.start_child(id: id)

    assert CrucibleRuntime.whereis(id) == pid

    assert Registry.lookup(SelfHostedInferenceCore.ProcessRegistry, {:instance, to_string(id)}) ==
             []
  end

  test "required unsupported tap fails closed at forward" do
    id = :"crucible-runtime-required-tap-#{System.unique_integer([:positive])}"
    assert {:ok, pid} = CrucibleRuntime.start_child(id: id)

    required_plan =
      TapPlan.new!([
        [id: "hidden", signal_type: :hidden_state, required?: true],
        [id: "logits", signal_type: :final_logits, required?: true]
      ])

    assert {:error, {:tap_compile_failed, report}} =
             CrucibleRuntime.forward(pid, required_plan, %{prompt: "hello"})

    assert report.required_missing == ["hidden"]
  end

  test "optional unsupported tap degrades but forward still succeeds" do
    id = :"crucible-runtime-optional-tap-#{System.unique_integer([:positive])}"
    assert {:ok, pid} = CrucibleRuntime.start_child(id: id)

    optional_plan =
      TapPlan.new!([
        [id: "hidden", signal_type: :hidden_state, required?: false],
        [id: "logits", signal_type: :final_logits, required?: true]
      ])

    assert {:ok, %Crucible.ForwardTrace{} = trace} =
             CrucibleRuntime.forward(pid, optional_plan, %{prompt: "hello"})

    assert trace.final_logits.signal_type == :final_logits
    assert trace.capability_report.optional_dropped == ["hidden"]
  end

  test "rejects invalid forward traces at the worker boundary" do
    id = :"crucible-runtime-invalid-trace-#{System.unique_integer([:positive])}"

    assert {:ok, pid} =
             CrucibleRuntime.start_child(
               id: id,
               provider_module: InvalidTraceCrucibleProvider
             )

    assert {:error, {:invalid_trace, :empty_signals}} =
             CrucibleRuntime.forward(pid, nil, %{prompt: "hello"})

    snapshot = CrucibleRuntime.snapshot(pid)
    assert snapshot.last_forward_ok? == false
    assert snapshot.last_error == {:invalid_trace, :empty_signals}
  end

  test "provider startup failures keep the runtime out of readiness" do
    id = :"crucible-runtime-provider-blocked-#{System.unique_integer([:positive])}"

    assert {:error, reason} =
             CrucibleRuntime.start_child(
               id: id,
               provider_module: FailingCrucibleProvider,
               provider_opts: [reason: {:unsupported_model, "unsupported/model"}]
             )

    assert inspect(reason) =~ "unsupported/model"
    refute CrucibleRuntime.whereis(id)
  end

  defp tap_plan do
    TapPlan.new!(
      [
        [id: "hidden", signal_type: :middle_residuals, layers: [0], required?: false],
        [id: "logits", signal_type: :final_logits, layers: [:final], required?: true]
      ],
      plan_id: "crucible-runtime-test"
    )
  end

  defp fixture_outputs(_input) do
    %{
      logits: Nx.tensor([[0.1, 0.4, 0.2]], type: :f32),
      hidden_states: {
        Nx.tensor([[1.0, 0.0]], type: :f32),
        Nx.tensor([[0.0, 1.0]], type: :f32),
        Nx.tensor([[1.0, 1.0]], type: :f32)
      },
      cache: %{blocks: {:block0}}
    }
  end
end
