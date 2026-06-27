defmodule SelfHostedInferenceCore.CrucibleRuntime.FormalProviderAdapter do
  @moduledoc """
  Adapts a formal `Crucible.Provider` module to the SHIC runtime provider API.

  SHIC keeps its supervision and lease API stable while formal providers migrate
  to the shared Crucible ABI. The adapter compiles tap plans before execution,
  carries capability reports into trace metadata, and preserves fail-closed
  behavior for unsupported required taps.
  """

  @behaviour SelfHostedInferenceCore.CrucibleRuntime.Provider

  alias Crucible.CapabilityReport
  alias CrucibleTap.TapPlan

  defstruct [:provider_module, :provider_state, :model_ref]

  @impl true
  def init(opts) when is_list(opts) do
    {provider_module, provider_opts} = Keyword.pop(opts, :provider_module)

    with :ok <- validate_provider_module(provider_module),
         {:ok, provider_state} <- provider_module.init(provider_opts) do
      {:ok,
       %__MODULE__{
         provider_module: provider_module,
         provider_state: provider_state,
         model_ref: Keyword.get(provider_opts, :model_ref, Keyword.get(provider_opts, :model_id))
       }}
    end
  end

  @impl true
  def forward(%__MODULE__{} = state, input, opts) do
    with {:ok, compiled_plan, capability_report} <- resolve_execution_plan(state, opts),
         {:ok, trace} <-
           state.provider_module.forward(
             state.provider_state,
             input,
             compiled_plan,
             Keyword.put(opts, :capability_report, capability_report)
           ) do
      {:ok, maybe_attach_capability_report(trace, capability_report)}
    end
  end

  @impl true
  def generate(%__MODULE__{} = state, input, opts) do
    with {:ok, compiled_plan, capability_report} <- resolve_execution_plan(state, opts),
         {:ok, result} <-
           state.provider_module.generate(
             state.provider_state,
             input,
             compiled_plan,
             Keyword.put(opts, :capability_report, capability_report)
           ) do
      {:ok, maybe_attach_capability_report(result, capability_report)}
    end
  end

  @impl true
  def capabilities(%__MODULE__{} = state) do
    case state.provider_module.capabilities(state.provider_state) do
      {:ok, report} -> report
      {:error, reason} -> %{error: reason, provider_kind: provider_kind(state)}
    end
  end

  @impl true
  def provider_kind(%__MODULE__{} = state),
    do: state.provider_module.provider_kind(state.provider_state)

  @impl true
  def model_id(%__MODULE__{} = state) do
    state.provider_module.model_ref(state.provider_state)
    |> Kernel.||(state.model_ref)
    |> model_ref_to_string()
  end

  @impl true
  def backend(%__MODULE__{} = state), do: state.provider_module.backend(state.provider_state)

  @impl true
  def surface_id(%__MODULE__{} = state) do
    case surface(state, []) do
      {:ok, %{metadata: metadata, adapter: adapter}} -> Map.get(metadata, :surface_id, adapter)
      {:error, _reason} -> nil
    end
  end

  @impl true
  def ready?(%__MODULE__{} = state), do: state.provider_module.ready?(state.provider_state)

  @impl true
  def tokenizer_loaded?(%__MODULE__{} = state), do: ready?(state)

  @impl true
  def model_loaded?(%__MODULE__{} = state), do: ready?(state)

  @impl true
  def state_machine(%__MODULE__{} = state) do
    base = [:init, :select_provider, :load_provider, :preflight_surface, :compile_tap_plan]

    if ready?(state), do: base ++ [:ready], else: base
  end

  @impl true
  def surface(%__MODULE__{} = state, opts) do
    model_ref = Keyword.get(opts, :model_ref, state.model_ref)
    state.provider_module.surface(state.provider_state, model_ref, opts)
  end

  @impl true
  def compile_tap_plan(%__MODULE__{} = state, %TapPlan{} = plan, opts) do
    with {:ok, surface} <- surface(state, opts),
         {:ok, compiled_plan} <-
           state.provider_module.compile(state.provider_state, plan, surface, opts),
         {:ok, capability_report} <- capability_report(state, plan, surface, opts) do
      {:ok, compiled_plan, capability_report}
    end
  end

  defp resolve_execution_plan(%__MODULE__{} = state, opts) do
    case Keyword.get(opts, :tap_plan) do
      %TapPlan{} = plan ->
        compile_tap_plan(state, plan, opts)

      nil ->
        {:ok, Keyword.get(opts, :compiled_plan), report_or_nil(state)}
    end
  end

  defp capability_report(%__MODULE__{} = state, %TapPlan{} = plan, surface, opts) do
    case CapabilityReport.negotiate(plan, surface,
           provider_kind: provider_kind(state),
           model_id: model_id(state),
           backend: backend(state),
           resource_budget: Keyword.get(opts, :resource_budget)
         ) do
      {:ok, _compiled_plan, report} -> {:ok, report}
      {:error, reason} -> {:error, reason}
    end
  end

  defp report_or_nil(%__MODULE__{} = state) do
    case capabilities(state) do
      %CapabilityReport{} = report -> report
      _other -> nil
    end
  end

  defp maybe_attach_capability_report(
         %Crucible.ForwardTrace{capability_report: nil} = trace,
         %CapabilityReport{} = report
       ),
       do: %{trace | capability_report: report}

  defp maybe_attach_capability_report(result, _capability_report), do: result

  defp validate_provider_module(provider_module) when is_atom(provider_module), do: :ok
  defp validate_provider_module(other), do: {:error, {:invalid_formal_provider_module, other}}

  defp model_ref_to_string(value) when is_binary(value), do: value
  defp model_ref_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp model_ref_to_string(nil), do: nil
  defp model_ref_to_string(value), do: inspect(value)
end
