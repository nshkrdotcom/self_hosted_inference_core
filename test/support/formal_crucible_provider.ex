defmodule SelfHostedInferenceCore.TestSupport.FormalCrucibleProvider do
  @moduledoc false

  @behaviour Crucible.Provider

  alias Crucible.Provider.ProviderHealth
  alias CrucibleTap.{Surface, TapPlan}

  defstruct model_id: "model:formal-fixture",
            backend: :formal_fixture,
            test_pid: nil,
            ready?: true

  @impl true
  def init(opts) do
    {:ok,
     %__MODULE__{
       model_id: Keyword.get(opts, :model_id, "model:formal-fixture"),
       backend: Keyword.get(opts, :backend, :formal_fixture),
       test_pid: Keyword.get(opts, :test_pid),
       ready?: Keyword.get(opts, :ready?, true)
     }}
  end

  @impl true
  def surface(%__MODULE__{} = state, _model_ref, _opts), do: {:ok, surface(state)}

  @impl true
  def capabilities(%__MODULE__{} = state) do
    {:ok,
     Crucible.CapabilityReport.new(
       provider_kind: :model,
       model_id: state.model_id,
       model_family: :example_transformer,
       backend: state.backend,
       supported: ["logits"]
     )}
  end

  @impl true
  def compile(%__MODULE__{} = state, %TapPlan{} = plan, %Surface{} = surface, opts) do
    notify(state, {:compile, plan.plan_id})

    case Crucible.CapabilityReport.negotiate(plan, surface,
           provider_kind: provider_kind(state),
           model_id: state.model_id,
           backend: state.backend,
           resource_budget: Keyword.get(opts, :resource_budget)
         ) do
      {:ok, compiled, _report} -> {:ok, compiled}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def forward(%__MODULE__{} = state, _inputs, compiled_plan, opts) do
    notify(state, {:forward, plan_id(compiled_plan)})

    trace_id = Keyword.get_lazy(opts, :trace_id, fn -> "formal-trace" end)
    run_id = Keyword.get(opts, :run_id, "formal-run")
    logits = Nx.tensor([[0.1, 0.4, 0.2]], type: :f32)
    summary = Crucible.TensorSummary.compute(logits, entropy: true, top_k: 3)

    signal =
      Crucible.SignalRecord.new!(
        signal_id: "formal-final-logits",
        trace_id: trace_id,
        run_id: run_id,
        signal_type: :final_logits,
        provider_kind: provider_kind(state),
        model_id: state.model_id,
        model_family: :example_transformer,
        backend: state.backend,
        dtype: summary.dtype,
        shape: summary.shape,
        rank: summary.rank,
        node_name: "lm_head.output",
        capture_method: :formal_contract_fixture,
        surface_id: :formal_fixture,
        capability_status: :captured,
        tensor_summary: summary
      )

    {:ok,
     Crucible.ForwardTrace.new!(
       trace_id: trace_id,
       run_id: run_id,
       provider_kind: provider_kind(state),
       model_id: state.model_id,
       model_family: :example_transformer,
       backend: state.backend,
       final_logits: signal,
       signals: [signal],
       capability_report: Keyword.get(opts, :capability_report),
       status: :ok,
       metadata: %{compiled_plan_id: plan_id(compiled_plan)}
     )}
  end

  @impl true
  def generate(%__MODULE__{} = state, inputs, compiled_plan, opts) do
    notify(state, {:generate, plan_id(compiled_plan)})

    {:ok,
     %{inputs: inputs, compiled_plan_id: plan_id(compiled_plan), report: opts[:capability_report]}}
  end

  @impl true
  def ready?(%__MODULE__{} = state), do: state.ready?

  @impl true
  def health(%__MODULE__{}) do
    ProviderHealth.new!(
      status: :ok,
      uptime_seconds: 1,
      last_latency_ms: 1.0,
      error_count: 0,
      memory_bytes: 1024,
      details: %{provider: :formal_fixture}
    )
  end

  @impl true
  def provider_kind(%__MODULE__{}), do: :model

  @impl true
  def model_ref(%__MODULE__{} = state), do: state.model_id

  @impl true
  def backend(%__MODULE__{} = state), do: state.backend

  @impl true
  def shutdown(%__MODULE__{}, _reason), do: :ok

  defp surface(%__MODULE__{} = state) do
    Surface.new!(
      adapter: :formal_fixture,
      model_family: :example_transformer,
      metadata: %{surface_id: :formal_fixture, model_id: state.model_id},
      nodes: [
        [
          id: "lm_head.output",
          signal_type: :final_logits,
          layer_name: "lm_head.output",
          layer_index: :final,
          operations: [:read],
          capture_modes: [:summary]
        ]
      ]
    )
  end

  defp plan_id(%{plan_id: plan_id}), do: plan_id
  defp plan_id(_compiled_plan), do: nil

  defp notify(%__MODULE__{test_pid: nil}, _message), do: :ok
  defp notify(%__MODULE__{test_pid: pid}, message), do: send(pid, {__MODULE__, message})
end
