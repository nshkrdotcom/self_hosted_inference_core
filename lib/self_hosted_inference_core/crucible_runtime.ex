defmodule SelfHostedInferenceCore.CrucibleRuntime do
  @moduledoc """
  Supervised Crucible runtime API for Bumblebee-backed forward and generation calls.
  """

  alias SelfHostedInferenceCore.{CrucibleRuntime.Worker, LeaseRef}

  @registry SelfHostedInferenceCore.ProcessRegistry
  @supervisor SelfHostedInferenceCore.CrucibleRuntimeSupervisor

  @type runtime_ref :: GenServer.server()
  @type lease :: LeaseRef.t()

  @spec child_spec(map() | keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    Worker.child_spec(opts)
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: Worker.start_link(opts)

  @spec start_child(map() | keyword()) :: DynamicSupervisor.on_start_child()
  def start_child(opts) do
    :ok = ensure_registry()
    :ok = ensure_supervisor()
    DynamicSupervisor.start_child(@supervisor, child_spec(opts))
  end

  @spec via(atom() | String.t()) :: {:via, Registry, {module(), {module(), atom() | String.t()}}}
  def via(id), do: {:via, Registry, {@registry, registry_key(id)}}

  @spec registry_key(atom() | String.t()) :: {module(), atom() | String.t()}
  def registry_key(id), do: {__MODULE__, id}

  @spec whereis(atom() | String.t()) :: pid() | nil
  def whereis(id) do
    case Registry.lookup(@registry, registry_key(id)) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  @spec capabilities(runtime_ref()) :: {:ok, map()} | {:error, term()}
  def capabilities(runtime_ref), do: GenServer.call(runtime_ref, :capabilities)

  @spec ready?(runtime_ref()) :: boolean()
  def ready?(runtime_ref), do: GenServer.call(runtime_ref, :ready?)

  @spec lease(runtime_ref(), keyword()) :: {:ok, lease()} | {:error, term()}
  def lease(runtime_ref, opts \\ []), do: GenServer.call(runtime_ref, {:lease, opts})

  @spec release(lease()) :: :ok
  def release(%LeaseRef{lease_ref: lease_ref, metadata: %{runtime_pid: pid}}) when is_pid(pid) do
    GenServer.call(pid, {:release, lease_ref})
  end

  def release(%LeaseRef{lease_ref: lease_ref, metadata: %{"runtime_pid" => pid}})
      when is_pid(pid) do
    GenServer.call(pid, {:release, lease_ref})
  end

  def release(%LeaseRef{}), do: :ok

  @spec release(runtime_ref(), String.t()) :: :ok
  def release(runtime_ref, lease_ref), do: GenServer.call(runtime_ref, {:release, lease_ref})

  @spec forward(runtime_ref(), term(), term(), keyword()) ::
          {:ok, CrucibleSignalTrace.ForwardTrace.t()} | {:error, term()}
  def forward(runtime_ref, tap_plan, input, opts \\ []),
    do: GenServer.call(runtime_ref, {:forward, tap_plan, input, opts}, call_timeout(opts))

  @spec generate(runtime_ref(), term(), term(), keyword()) :: {:ok, term()} | {:error, term()}
  def generate(runtime_ref, tap_plan, input, opts \\ []),
    do: GenServer.call(runtime_ref, {:generate, tap_plan, input, opts}, call_timeout(opts))

  @spec snapshot(runtime_ref()) :: map()
  def snapshot(runtime_ref), do: GenServer.call(runtime_ref, :snapshot)

  @spec list_snapshots() :: [map()]
  def list_snapshots do
    @supervisor
    |> DynamicSupervisor.which_children()
    |> Enum.flat_map(fn {_id, pid, _type, _modules} ->
      try do
        [snapshot(pid)]
      catch
        :exit, _reason -> []
      end
    end)
    |> Enum.sort_by(&to_string(&1.id))
  end

  defp call_timeout(opts), do: Keyword.get(opts, :timeout, 30_000)

  defp ensure_registry do
    case Process.whereis(@registry) do
      nil ->
        case Registry.start_link(keys: :unique, name: @registry) do
          {:ok, pid} ->
            Process.unlink(pid)
            :ok

          {:error, {:already_started, _pid}} ->
            :ok

          {:error, reason} ->
            exit(reason)
        end

      _pid ->
        :ok
    end
  end

  defp ensure_supervisor do
    case Process.whereis(@supervisor) do
      nil ->
        case DynamicSupervisor.start_link(strategy: :one_for_one, name: @supervisor) do
          {:ok, pid} ->
            Process.unlink(pid)
            :ok

          {:error, {:already_started, _pid}} ->
            :ok

          {:error, reason} ->
            exit(reason)
        end

      _pid ->
        :ok
    end
  end
end
