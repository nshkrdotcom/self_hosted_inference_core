defmodule SelfHostedInferenceCore.RuntimeRegistry do
  @moduledoc false

  alias SelfHostedInferenceCore.{Backend, RuntimeInstance}

  @registry SelfHostedInferenceCore.ProcessRegistry
  @supervisor SelfHostedInferenceCore.RuntimeSupervisor

  @spec ensure_instance(Backend.StartupPlan.t(), module()) ::
          {:ok, pid(), boolean()} | {:error, term()}
  def ensure_instance(%Backend.StartupPlan{instance_key: instance_id} = plan, backend_module)
      when is_binary(instance_id) do
    child_spec =
      RuntimeInstance.child_spec(
        name: via(instance_id),
        plan: plan,
        backend_module: backend_module
      )

    case DynamicSupervisor.start_child(@supervisor, child_spec) do
      {:ok, pid} ->
        {:ok, pid, false}

      {:error, {:already_started, pid}} ->
        {:ok, pid, true}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec whereis(String.t()) :: pid() | nil
  def whereis(instance_id) when is_binary(instance_id) do
    case Registry.lookup(@registry, {:instance, instance_id}) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  @spec list_instances() :: [SelfHostedInferenceCore.RuntimeSnapshot.t()]
  def list_instances do
    @supervisor
    |> DynamicSupervisor.which_children()
    |> Enum.flat_map(fn {_id, pid, _type, _modules} ->
      case snapshot_instance(pid) do
        {:ok, snapshot} -> [snapshot]
        :error -> []
      end
    end)
    |> Enum.sort_by(& &1.instance_id)
  end

  @spec stop_instance(String.t()) :: :ok
  def stop_instance(instance_id) when is_binary(instance_id) do
    case whereis(instance_id) do
      pid when is_pid(pid) -> RuntimeInstance.stop(pid)
      nil -> :ok
    end
  end

  @spec stop_all_instances() :: :ok
  def stop_all_instances do
    Enum.each(list_instances(), fn snapshot ->
      stop_instance(snapshot.instance_id)
    end)

    :ok
  end

  defp via(instance_id), do: {:via, Registry, {@registry, {:instance, instance_id}}}

  defp snapshot_instance(pid) when is_pid(pid) do
    {:ok, RuntimeInstance.snapshot(pid)}
  catch
    :exit, _reason -> :error
  end
end
