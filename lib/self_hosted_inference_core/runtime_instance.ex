defmodule SelfHostedInferenceCore.RuntimeInstance do
  @moduledoc false

  use GenServer

  alias ExecutionPlane.Process.Transport

  alias SelfHostedInferenceCore.{
    Backend,
    EndpointDescriptor,
    LeaseRef,
    RuntimeSnapshot
  }

  @default_await_timeout_ms 5_000

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.fetch!(opts, :name)},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    plan = Keyword.fetch!(opts, :plan)
    backend_module = Keyword.fetch!(opts, :backend_module)
    GenServer.start_link(__MODULE__, {plan, backend_module}, name: name)
  end

  @spec await_ready(pid(), timeout()) :: {:ok, RuntimeSnapshot.t()} | {:error, term()}
  def await_ready(pid, timeout_ms \\ @default_await_timeout_ms) when is_pid(pid) do
    GenServer.call(pid, :await_ready, timeout_ms)
  end

  @spec snapshot(pid()) :: RuntimeSnapshot.t()
  def snapshot(pid) when is_pid(pid), do: GenServer.call(pid, :snapshot)

  @spec acquire_lease(pid(), keyword()) ::
          {:ok, %{endpoint: EndpointDescriptor.t(), lease: LeaseRef.t()}} | {:error, term()}
  def acquire_lease(pid, opts \\ []) when is_pid(pid) do
    GenServer.call(pid, {:acquire_lease, opts})
  end

  @spec release_lease(pid(), String.t()) :: :ok
  def release_lease(pid, lease_ref) when is_pid(pid) and is_binary(lease_ref) do
    GenServer.call(pid, {:release_lease, lease_ref})
  end

  @spec publish_endpoint(pid()) :: {:ok, EndpointDescriptor.t()} | {:error, term()}
  def publish_endpoint(pid) when is_pid(pid), do: GenServer.call(pid, :publish_endpoint)

  @spec stop(pid()) :: :ok
  def stop(pid) when is_pid(pid) do
    GenServer.stop(pid, :normal)
  catch
    :exit, _reason -> :ok
  end

  @impl true
  def init({%Backend.StartupPlan{} = plan, backend_module}) do
    Process.flag(:trap_exit, true)

    state = %{
      backend_module: backend_module,
      plan: plan,
      instance_id: plan.instance_key,
      transport_pid: nil,
      transport_tag: make_ref(),
      backend_state: plan.backend_state,
      lifecycle_status: :starting,
      health_status: :unavailable,
      endpoint: nil,
      leases: %{},
      lease_timers: %{},
      waiters: [],
      inserted_at_ms: now_ms(),
      ready_at_ms: nil,
      readiness_timer: nil,
      readiness_timeout_timer: nil,
      health_timer: nil,
      idle_timer: nil
    }

    {:ok, state, {:continue, :bootstrap}}
  end

  @impl true
  def handle_continue(:bootstrap, %{plan: %Backend.StartupPlan{transport: nil}} = state) do
    {:noreply, schedule_readiness(state)}
  end

  def handle_continue(
        :bootstrap,
        %{plan: %Backend.StartupPlan{transport: %Backend.TransportPlan{} = transport}} = state
      ) do
    start_opts =
      [
        command: transport.command,
        subscriber: {self(), state.transport_tag},
        stdout_mode: transport.stdout_mode,
        stdin_mode: transport.stdin_mode,
        pty?: transport.pty?,
        buffer_events_until_subscribe?: true,
        replay_stderr_on_subscribe?: true
      ]
      |> Keyword.merge(execution_surface_opts(transport.execution_surface))

    case Transport.start(start_opts) do
      {:ok, transport_pid} ->
        {:noreply, state |> Map.put(:transport_pid, transport_pid) |> schedule_readiness()}

      {:error, reason} ->
        {:stop, {:shutdown, {:transport_start_failed, reason}},
         reply_waiters(state, {:error, {:transport_start_failed, reason}})}
    end
  end

  @impl true
  def handle_call(:await_ready, _from, %{lifecycle_status: :ready} = state) do
    {:reply, {:ok, snapshot_from_state(state)}, state}
  end

  def handle_call(:await_ready, _from, %{lifecycle_status: :failed} = state) do
    {:reply, {:error, :failed}, state}
  end

  def handle_call(:await_ready, from, state) do
    {:noreply, update_in(state.waiters, &[from | &1])}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, snapshot_from_state(state), state}
  end

  def handle_call(:publish_endpoint, _from, %{endpoint: %EndpointDescriptor{} = endpoint} = state) do
    {:reply, {:ok, endpoint}, state}
  end

  def handle_call(:publish_endpoint, _from, state) do
    {:reply, {:error, :not_ready}, state}
  end

  def handle_call(
        {:acquire_lease, opts},
        _from,
        %{endpoint: %EndpointDescriptor{} = endpoint} = state
      ) do
    owner_ref = Keyword.get(opts, :owner_ref)
    ttl_ms = Keyword.get(opts, :ttl_ms)
    renewable? = Keyword.get(opts, :renewable?, true)
    lease_ref = lease_token()

    lease =
      LeaseRef.new!(
        lease_ref: lease_ref,
        owner_ref: owner_ref,
        ttl_ms: ttl_ms,
        renewable?: renewable?,
        metadata: %{instance_id: state.instance_id}
      )

    timer =
      if is_integer(ttl_ms) and ttl_ms > 0 do
        Process.send_after(self(), {:lease_expired, lease_ref}, ttl_ms)
      end

    state =
      state
      |> cancel_idle_timer()
      |> put_in([:leases, lease_ref], lease)
      |> put_in([:lease_timers, lease_ref], timer)

    {:reply,
     {:ok, %{endpoint: %EndpointDescriptor{endpoint | lease_ref: lease_ref}, lease: lease}},
     state}
  end

  def handle_call({:acquire_lease, _opts}, _from, state) do
    {:reply, {:error, :not_ready}, state}
  end

  def handle_call({:release_lease, lease_ref}, _from, state) do
    {:reply, :ok, release_lease_internal(state, lease_ref)}
  end

  @impl true
  def handle_info(:poll_readiness, %{lifecycle_status: :starting} = state) do
    case state.backend_module.probe_readiness(state.backend_state) do
      {:pending, backend_state} ->
        {:noreply, state |> Map.put(:backend_state, backend_state) |> reschedule_readiness()}

      {:ready, endpoint_fields, backend_state} ->
        {:noreply, state |> Map.put(:backend_state, backend_state) |> mark_ready(endpoint_fields)}

      {:error, reason, backend_state} ->
        state = state |> Map.put(:backend_state, backend_state) |> reply_waiters({:error, reason})
        {:stop, {:shutdown, {:readiness_failed, reason}}, state}
    end
  end

  def handle_info(:poll_readiness, state) do
    {:noreply, state}
  end

  def handle_info(:poll_health, %{lifecycle_status: :ready} = state) do
    case state.backend_module.health_check(state.backend_state) do
      {:ok, health_status, _metadata, backend_state} ->
        {:noreply,
         state
         |> Map.put(:backend_state, backend_state)
         |> Map.put(:health_status, health_status)
         |> reschedule_health()}

      {:error, _reason, backend_state} ->
        {:noreply,
         state
         |> Map.put(:backend_state, backend_state)
         |> Map.put(:health_status, :unavailable)
         |> reschedule_health()}
    end
  end

  def handle_info(:poll_health, state) do
    {:noreply, state}
  end

  def handle_info(:readiness_timeout, %{lifecycle_status: :starting} = state) do
    state = reply_waiters(state, {:error, :readiness_timeout})
    {:stop, {:shutdown, :readiness_timeout}, state}
  end

  def handle_info(:readiness_timeout, state) do
    {:noreply, state}
  end

  def handle_info(:idle_shutdown, %{lifecycle_status: :ready} = state) do
    {:stop, :normal, state}
  end

  def handle_info({:lease_expired, lease_ref}, state) do
    {:noreply, release_lease_internal(state, lease_ref)}
  end

  def handle_info(message, state) do
    case Transport.extract_event(message, state.transport_tag) do
      {:ok, event} ->
        handle_transport_event(event, state)

      :error ->
        {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    cancel_timer(state.readiness_timer)
    cancel_timer(state.readiness_timeout_timer)
    cancel_timer(state.health_timer)
    cancel_timer(state.idle_timer)

    Enum.each(state.lease_timers, fn {_lease_ref, timer} ->
      cancel_timer(timer)
    end)

    if function_exported?(state.backend_module, :shutdown, 2) do
      _ = state.backend_module.shutdown(state.backend_state, state.transport_pid)
    end

    if is_pid(state.transport_pid) do
      Transport.close(state.transport_pid)
    end

    :ok
  end

  defp handle_transport_event(event, state) do
    result =
      if function_exported?(state.backend_module, :handle_transport_event, 2) do
        state.backend_module.handle_transport_event(event, state.backend_state)
      else
        default_transport_event(event, state.backend_state)
      end

    case result do
      {:pending, backend_state} ->
        {:noreply, %{state | backend_state: backend_state}}

      {:ready, endpoint_fields, backend_state} ->
        {:noreply, state |> Map.put(:backend_state, backend_state) |> mark_ready(endpoint_fields)}

      {:stop, reason, backend_state} ->
        state = state |> Map.put(:backend_state, backend_state) |> reply_waiters({:error, reason})
        {:stop, stop_reason(state, reason), state}
    end
  end

  defp default_transport_event({:exit, _exit}, backend_state),
    do: {:stop, :transport_exit, backend_state}

  defp default_transport_event(_event, backend_state), do: {:pending, backend_state}

  defp schedule_readiness(state) do
    cancel_timer(state.readiness_timer)
    cancel_timer(state.readiness_timeout_timer)

    %{state | readiness_timer: Process.send_after(self(), :poll_readiness, 0)}
    |> Map.put(
      :readiness_timeout_timer,
      Process.send_after(self(), :readiness_timeout, state.plan.ready_timeout_ms)
    )
  end

  defp reschedule_readiness(state) do
    cancel_timer(state.readiness_timer)

    %{
      state
      | readiness_timer:
          Process.send_after(self(), :poll_readiness, state.plan.readiness_interval_ms)
    }
  end

  defp reschedule_health(%{plan: %Backend.StartupPlan{health_interval_ms: nil}} = state),
    do: state

  defp reschedule_health(state) do
    cancel_timer(state.health_timer)

    %{
      state
      | health_timer: Process.send_after(self(), :poll_health, state.plan.health_interval_ms)
    }
  end

  defp mark_ready(state, endpoint_fields) do
    endpoint = build_endpoint(state, endpoint_fields)

    state = %{
      state
      | endpoint: endpoint,
        lifecycle_status: :ready,
        health_status: :healthy,
        ready_at_ms: now_ms()
    }

    cancel_timer(state.readiness_timer)
    cancel_timer(state.readiness_timeout_timer)

    state
    |> Map.put(:readiness_timer, nil)
    |> Map.put(:readiness_timeout_timer, nil)
    |> reply_waiters({:ok, snapshot_from_state(state)})
    |> reschedule_health()
  end

  defp build_endpoint(state, endpoint_fields) when is_map(endpoint_fields) do
    template = Map.merge(state.plan.endpoint_template, endpoint_fields)

    EndpointDescriptor.new!(
      endpoint_id: "#{state.instance_id}:endpoint",
      runtime_kind: :service,
      management_mode: state.plan.management_mode,
      target_class: :self_hosted_endpoint,
      protocol: Map.get(template, :protocol, :openai_chat_completions),
      base_url: Map.fetch!(template, :base_url),
      headers: Map.get(template, :headers, %{}),
      provider_identity: Map.get(template, :provider_identity, state.plan.backend),
      model_identity: Map.get(template, :model_identity, state.instance_id),
      source_runtime: Map.get(template, :source_runtime, state.plan.backend),
      source_runtime_ref: Map.get(template, :source_runtime_ref),
      lease_ref: nil,
      health_ref: Map.get(template, :health_ref),
      boundary_ref: Map.get(template, :boundary_ref),
      capabilities: Map.get(template, :capabilities, %{}),
      metadata: Map.get(template, :metadata, %{})
    )
  end

  defp release_lease_internal(state, lease_ref) do
    cancel_timer(Map.get(state.lease_timers, lease_ref))

    state =
      state
      |> update_in([:leases], &Map.delete(&1, lease_ref))
      |> update_in([:lease_timers], &Map.delete(&1, lease_ref))

    if map_size(state.leases) == 0 and state.plan.stop_when_idle? do
      schedule_idle_shutdown(state)
    else
      state
    end
  end

  defp schedule_idle_shutdown(%{plan: %Backend.StartupPlan{idle_shutdown_ms: nil}} = state) do
    %{state | idle_timer: Process.send_after(self(), :idle_shutdown, 0)}
  end

  defp schedule_idle_shutdown(state) do
    cancel_timer(state.idle_timer)
    %{state | idle_timer: Process.send_after(self(), :idle_shutdown, state.plan.idle_shutdown_ms)}
  end

  defp cancel_idle_timer(state) do
    cancel_timer(state.idle_timer)
    %{state | idle_timer: nil}
  end

  defp snapshot_from_state(state) do
    %RuntimeSnapshot{
      instance_id: state.instance_id,
      backend: state.plan.backend,
      startup_kind: state.plan.startup_kind,
      management_mode: state.plan.management_mode,
      lifecycle_status: state.lifecycle_status,
      health_status: state.health_status,
      lease_count: map_size(state.leases),
      endpoint: state.endpoint,
      inserted_at_ms: state.inserted_at_ms,
      ready_at_ms: state.ready_at_ms,
      metadata: state.plan.metadata
    }
  end

  defp reply_waiters(state, result) do
    Enum.each(state.waiters, fn from ->
      GenServer.reply(from, result)
    end)

    %{state | waiters: []}
  end

  defp execution_surface_opts(nil), do: []

  defp execution_surface_opts(%ExecutionPlane.Placements.Surface{} = surface) do
    surface
    |> Map.from_struct()
    |> Map.delete(:__struct__)
    |> Map.update!(:surface_kind, &normalize_surface_kind/1)
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == [] or value == %{} end)
    |> Enum.into([])
  end

  defp execution_surface_opts(surface) when is_map(surface) do
    surface
    |> Map.new(fn
      {:__struct__, _value} -> nil
      {"surface_kind", value} -> {:surface_kind, normalize_surface_kind(value)}
      {:surface_kind, value} -> {:surface_kind, normalize_surface_kind(value)}
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      pair -> pair
    end)
    |> Enum.reject(fn
      nil -> true
      {_key, value} -> is_nil(value) or value == [] or value == %{}
    end)
  end

  defp execution_surface_opts(opts) when is_list(opts), do: opts

  defp normalize_surface_kind("local_subprocess"), do: :local_subprocess
  defp normalize_surface_kind("ssh_exec"), do: :ssh_exec
  defp normalize_surface_kind("guest_bridge"), do: :guest_bridge
  defp normalize_surface_kind(value) when is_atom(value), do: value
  defp normalize_surface_kind(_value), do: :local_subprocess

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)

  defp lease_token do
    "lease-" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end

  defp now_ms do
    System.system_time(:millisecond)
  end

  defp stop_reason(%{lifecycle_status: :starting}, reason), do: {:shutdown, reason}
  defp stop_reason(_state, reason), do: reason
end
