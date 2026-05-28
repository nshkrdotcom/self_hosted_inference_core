defmodule SelfHostedInferenceCore.CrucibleRuntime.Worker do
  @moduledoc false

  use GenServer

  alias SelfHostedInferenceCore.{
    CrucibleRuntime,
    CrucibleRuntime.FixtureProvider,
    LeaseRef
  }

  def child_spec(opts) when is_map(opts), do: child_spec(Map.to_list(opts))

  def child_spec(opts) when is_list(opts) do
    id = Keyword.fetch!(opts, :id)

    %{
      id: {__MODULE__, id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent
    }
  end

  def start_link(opts) when is_map(opts), do: start_link(Map.to_list(opts))

  def start_link(opts) when is_list(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: CrucibleRuntime.via(id))
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    with {:ok, provider_module} <- resolve_provider_module(opts),
         {:ok, provider_state} <- provider_module.init(provider_opts(opts)) do
      state = %{
        id: Keyword.fetch!(opts, :id),
        provider_module: provider_module,
        provider_state: provider_state,
        ready?: provider_module.ready?(provider_state),
        last_forward_ok?: false,
        last_error: nil,
        leases: %{},
        lease_timers: %{},
        started_at_ms: now_ms()
      }

      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  rescue
    error -> {:stop, {:provider_start_failed, Exception.message(error)}}
  end

  @impl true
  def handle_call(:capabilities, _from, state) do
    {:reply, {:ok, capabilities(state)}, state}
  end

  def handle_call(:ready?, _from, state) do
    {:reply, state.ready?, state}
  end

  def handle_call({:lease, opts}, _from, %{ready?: true} = state) do
    lease_ref =
      "crucible-lease-" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))

    ttl_ms = Keyword.get(opts, :ttl_ms)

    lease =
      LeaseRef.new!(
        lease_ref: lease_ref,
        owner_ref: Keyword.get(opts, :owner_ref),
        ttl_ms: ttl_ms,
        renewable?: Keyword.get(opts, :renewable?, true),
        metadata: %{
          runtime: state.id,
          runtime_pid: self(),
          provider_kind: provider_kind(state),
          backend: backend(state),
          surface: surface_id(state),
          capabilities: capabilities(state)
        }
      )

    timer =
      if is_integer(ttl_ms) and ttl_ms > 0 do
        Process.send_after(self(), {:lease_expired, lease_ref}, ttl_ms)
      end

    :telemetry.execute(
      [:self_hosted_inference_core, :lease, :acquire],
      %{count: 1},
      %{runtime_kind: :crucible, runtime: state.id, lease_ref: lease_ref}
    )

    {:reply, {:ok, lease}, put_lease(state, lease_ref, lease, timer)}
  end

  def handle_call({:lease, _opts}, _from, state), do: {:reply, {:error, :not_ready}, state}

  def handle_call({:release, lease_ref}, _from, state) do
    {:reply, :ok, release_lease(state, lease_ref)}
  end

  def handle_call({:forward, _tap_plan, input, opts}, _from, %{ready?: true} = state) do
    opts = Keyword.put_new(opts, :trace_id, trace_id(state))

    case state.provider_module.forward(state.provider_state, input, opts) do
      {:ok, %Crucible.ForwardTrace{} = trace} ->
        {:reply, {:ok, trace}, %{state | last_forward_ok?: true, last_error: nil}}

      {:error, reason} ->
        {:reply, {:error, reason}, %{state | last_forward_ok?: false, last_error: reason}}
    end
  end

  def handle_call({:forward, _tap_plan, _input, _opts}, _from, state) do
    {:reply, {:error, :not_ready}, state}
  end

  def handle_call({:generate, _tap_plan, input, opts}, _from, %{ready?: true} = state) do
    case state.provider_module.generate(state.provider_state, input, opts) do
      {:ok, result} ->
        {:reply, {:ok, result}, %{state | last_error: nil}}

      {:error, reason} ->
        {:reply, {:error, reason}, %{state | last_error: reason}}
    end
  end

  def handle_call({:generate, _tap_plan, _input, _opts}, _from, state) do
    {:reply, {:error, :not_ready}, state}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, snapshot(state), state}
  end

  @impl true
  def handle_info({:lease_expired, lease_ref}, state) do
    {:noreply, release_lease(state, lease_ref)}
  end

  def handle_info({:EXIT, _pid, _reason}, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.lease_timers, fn {_lease_ref, timer} -> cancel_timer(timer) end)
    :ok
  end

  defp resolve_provider_module(opts) do
    case Keyword.get(opts, :provider_module, Keyword.get(opts, :provider)) do
      nil ->
        if Keyword.get(opts, :live_model?, false) do
          {:error, :missing_live_crucible_provider}
        else
          {:ok, FixtureProvider}
        end

      provider_module when is_atom(provider_module) ->
        if Code.ensure_loaded?(provider_module) do
          {:ok, provider_module}
        else
          {:error, {:provider_not_loaded, provider_module}}
        end

      other ->
        {:error, {:invalid_provider_module, other}}
    end
  end

  defp provider_opts(opts), do: Keyword.get(opts, :provider_opts, opts)

  defp put_lease(state, lease_ref, lease, timer) do
    state
    |> put_in([:leases, lease_ref], lease)
    |> put_in([:lease_timers, lease_ref], timer)
  end

  defp release_lease(state, lease_ref) do
    cancel_timer(Map.get(state.lease_timers, lease_ref))

    if Map.has_key?(state.leases, lease_ref) do
      :telemetry.execute(
        [:self_hosted_inference_core, :lease, :release],
        %{count: 1},
        %{runtime_kind: :crucible, runtime: state.id, lease_ref: lease_ref}
      )
    end

    state
    |> update_in([:leases], &Map.delete(&1, lease_ref))
    |> update_in([:lease_timers], &Map.delete(&1, lease_ref))
  end

  defp snapshot(state) do
    %{
      id: state.id,
      ready?: state.ready?,
      runtime_id: to_string(state.id),
      provider_kind: provider_kind(state),
      model_id: model_id(state),
      tokenizer_loaded?: tokenizer_loaded?(state),
      model_loaded?: model_loaded?(state),
      backend: backend(state),
      surface: surface_id(state),
      lease_count: map_size(state.leases),
      active_leases: map_size(state.leases),
      capabilities: capabilities(state),
      last_forward_ok?: state.last_forward_ok?,
      last_error: state.last_error,
      state_machine: state_machine(state),
      started_at_ms: state.started_at_ms
    }
  end

  defp capabilities(state), do: state.provider_module.capabilities(state.provider_state)
  defp provider_kind(state), do: state.provider_module.provider_kind(state.provider_state)
  defp model_id(state), do: state.provider_module.model_id(state.provider_state)
  defp backend(state), do: state.provider_module.backend(state.provider_state)
  defp surface_id(state), do: state.provider_module.surface_id(state.provider_state)
  defp tokenizer_loaded?(state), do: state.provider_module.tokenizer_loaded?(state.provider_state)
  defp model_loaded?(state), do: state.provider_module.model_loaded?(state.provider_state)
  defp state_machine(state), do: state.provider_module.state_machine(state.provider_state)

  defp trace_id(state),
    do: "crucible-runtime:#{state.id}:#{System.unique_integer([:positive])}"

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)

  defp now_ms, do: System.system_time(:millisecond)
end
