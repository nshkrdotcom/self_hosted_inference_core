defmodule SelfHostedInferenceCore.CrucibleRuntimeTest do
  use ExUnit.Case, async: false

  alias CrucibleBumblebee.ExampleSurface
  alias CruciblePolicy.SteeringPlan
  alias CrucibleSignalTrace.ForwardTrace
  alias CrucibleTap.TapPlan
  alias SelfHostedInferenceCore.{CrucibleRuntime, Health, LeaseRef, Readiness}

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
               model_ref: "model:fixture",
               surface_module: ExampleSurface,
               serving_tap_plan: tap_plan,
               predict_fun: &fixture_outputs/1
             )

    assert CrucibleRuntime.whereis(id) == pid
    assert CrucibleRuntime.ready?(pid)
    assert {:ok, capabilities} = CrucibleRuntime.capabilities(pid)
    assert capabilities.surface == :example_transformer

    assert {:ok, %LeaseRef{} = lease} = CrucibleRuntime.lease(pid, owner_ref: "test")
    assert lease.metadata.runtime == id

    assert {:ok, %ForwardTrace{} = trace} =
             CrucibleRuntime.forward(pid, tap_plan, %{prompt: "hello"})

    assert trace.model_ref == "model:fixture"
    assert trace.final_logits.signal_type == :final_logits

    assert :ok = CrucibleRuntime.release(lease)
    assert CrucibleRuntime.snapshot(pid).lease_count == 0
  end

  test "generation uses configured custom loop" do
    id = :"crucible-runtime-generation-#{System.unique_integer([:positive])}"
    generation_runner = fn input, %SteeringPlan{} = plan -> %{input: input, mode: plan.mode} end

    assert {:ok, pid} =
             CrucibleRuntime.start_child(
               id: id,
               generation_runner: generation_runner,
               surface_module: ExampleSurface
             )

    steering = SteeringPlan.new!(trace_id: "trace-1", token_biases: %{1 => 1.0})

    assert {:ok, %{input: "prompt", mode: :token_boundary}} =
             CrucibleRuntime.generate(pid, nil, "prompt", steering_plan: steering)
  end

  test "health and readiness include crucible runtimes" do
    id = :"crucible-runtime-health-#{System.unique_integer([:positive])}"
    assert {:ok, _pid} = CrucibleRuntime.start_child(id: id, surface_module: ExampleSurface)

    assert Readiness.ready?()
    assert %{crucible_runtimes: [snapshot | _]} = Health.report()
    assert snapshot.ready?
  end

  test "registry key does not collide with legacy runtime instance keys" do
    id = :"crucible-runtime-registry-#{System.unique_integer([:positive])}"
    assert {:ok, pid} = CrucibleRuntime.start_child(id: id, surface_module: ExampleSurface)

    assert CrucibleRuntime.whereis(id) == pid

    assert Registry.lookup(SelfHostedInferenceCore.ProcessRegistry, {:instance, to_string(id)}) ==
             []
  end

  test "live worker rejects readiness when model loading cannot preflight" do
    id = :"crucible-runtime-live-blocked-#{System.unique_integer([:positive])}"

    assert {:error, reason} =
             CrucibleRuntime.start_child(
               id: id,
               live_model?: true,
               model_id: "unsupported/model",
               backend: :binary
             )

    assert inspect(reason) =~ "unsupported/model"
    refute CrucibleRuntime.whereis(id)
  end

  defp tap_plan do
    TapPlan.new!(
      [
        [id: "hidden", signal_type: :middle_residuals, layers: [0]],
        [id: "logits", signal_type: :final_logits, layers: [:final]]
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
