defmodule SelfHostedInferenceCore.CrucibleRuntime.FixtureProvider do
  @moduledoc """
  Deterministic provider used by core tests and offline examples.

  This provider keeps the runtime kernel testable without depending on a model
  adapter package. It emits the same canonical Crucible trace structs as live
  providers, using bounded tensor summaries only.
  """

  @behaviour SelfHostedInferenceCore.CrucibleRuntime.Provider

  @default_model_id "model:fixture"
  @surface_id :example_transformer
  @model_family :example_transformer

  defstruct [
    :model_id,
    :backend,
    :predict_fun,
    :generation_runner
  ]

  @impl true
  def init(opts) when is_list(opts) do
    {:ok,
     %__MODULE__{
       model_id: Keyword.get(opts, :model_id, @default_model_id),
       backend: Keyword.get(opts, :backend_preference, Keyword.get(opts, :backend, :fixture)),
       predict_fun: Keyword.get(opts, :predict_fun, &default_predict_fun/1),
       generation_runner: Keyword.get(opts, :generation_runner)
     }}
  end

  @impl true
  def forward(%__MODULE__{} = state, input, opts) do
    trace_id = Keyword.get_lazy(opts, :trace_id, &trace_id/0)
    run_id = Keyword.get_lazy(opts, :run_id, &run_id/0)
    outputs = state.predict_fun.(input)
    logits = Map.fetch!(outputs, :logits)
    prompt = prompt_from_input(input)

    final_logits =
      signal_record(logits, %{
        signal_id: "sig_final_logits",
        trace_id: trace_id,
        run_id: run_id,
        signal_type: :final_logits,
        node_name: "final_logits",
        capture_method: :fixture_predict_fun,
        model_id: state.model_id,
        backend: state.backend
      })

    trace =
      Crucible.ForwardTrace.new!(
        trace_id: trace_id,
        run_id: run_id,
        provider_kind: provider_kind(state),
        model_id: state.model_id,
        model_family: @model_family,
        backend: state.backend,
        prompt_digest: CrucibleSignalTrace.Digest.prefixed_text(prompt),
        final_logits: final_logits,
        signals: [final_logits],
        capability_report: capabilities(state),
        status: :ok,
        metadata: %{surface_id: @surface_id}
      )

    {:ok, trace}
  rescue
    error -> {:error, {:fixture_forward_failed, Exception.message(error)}}
  end

  @impl true
  def generate(%__MODULE__{generation_runner: nil}, _input, _opts),
    do: {:error, :generation_unavailable}

  def generate(%__MODULE__{generation_runner: runner}, input, opts) when is_function(runner, 2) do
    input
    |> runner.(Keyword.get(opts, :steering_plan))
    |> normalize_result()
  end

  def generate(%__MODULE__{generation_runner: runner}, input, opts) when is_function(runner, 3) do
    input
    |> runner.(Keyword.get(opts, :steering_plan), opts)
    |> normalize_result()
  end

  @impl true
  def capabilities(%__MODULE__{} = state) do
    %{
      provider_kind: provider_kind(state),
      model_id: state.model_id,
      model_family: @model_family,
      backend: state.backend,
      surface: @surface_id,
      final_logits: true,
      hidden_states: true,
      attentions: true,
      cache_metadata: true,
      token_boundary_steering: true
    }
  end

  @impl true
  def provider_kind(%__MODULE__{}), do: :fixture

  @impl true
  def model_id(%__MODULE__{} = state), do: state.model_id

  @impl true
  def backend(%__MODULE__{} = state), do: state.backend

  @impl true
  def surface_id(%__MODULE__{}), do: @surface_id

  @impl true
  def ready?(%__MODULE__{}), do: true

  @impl true
  def tokenizer_loaded?(%__MODULE__{}), do: true

  @impl true
  def model_loaded?(%__MODULE__{}), do: true

  @impl true
  def state_machine(%__MODULE__{}) do
    [
      :init,
      :select_provider,
      :load_tokenizer,
      :load_model,
      :preflight_surface,
      :compile_tap_plan,
      :ready
    ]
  end

  defp signal_record(logits, attrs) do
    summary = Crucible.TensorSummary.compute(logits, entropy: true, top_k: 10)

    Crucible.SignalRecord.new!(
      signal_id: Map.fetch!(attrs, :signal_id),
      trace_id: Map.fetch!(attrs, :trace_id),
      run_id: Map.fetch!(attrs, :run_id),
      signal_type: Map.fetch!(attrs, :signal_type),
      provider_kind: :fixture,
      model_id: Map.fetch!(attrs, :model_id),
      model_family: @model_family,
      backend: Map.fetch!(attrs, :backend),
      dtype: summary.dtype,
      shape: summary.shape,
      rank: summary.rank,
      node_name: Map.fetch!(attrs, :node_name),
      capture_method: Map.fetch!(attrs, :capture_method),
      surface_id: @surface_id,
      capability_status: :captured,
      tensor_summary: summary,
      metadata: %{}
    )
  end

  defp normalize_result({:ok, _value} = result), do: result
  defp normalize_result({:error, _reason} = result), do: result
  defp normalize_result(value), do: {:ok, value}

  defp default_predict_fun(_input) do
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

  defp prompt_from_input(%{prompt: prompt}) when is_binary(prompt), do: prompt
  defp prompt_from_input(%{"prompt" => prompt}) when is_binary(prompt), do: prompt
  defp prompt_from_input(prompt) when is_binary(prompt), do: prompt
  defp prompt_from_input(_input), do: "fixture"

  defp trace_id, do: "tr_#{System.unique_integer([:positive])}"
  defp run_id, do: "run_#{System.unique_integer([:positive])}"
end
