defmodule SelfHostedInferenceCore.BackendRegistry do
  @moduledoc false

  use GenServer

  @name __MODULE__

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  def register(module) when is_atom(module), do: GenServer.call(@name, {:register, module})
  def unregister(backend) when is_atom(backend), do: GenServer.call(@name, {:unregister, backend})

  def fetch_module(backend) when is_atom(backend),
    do: GenServer.call(@name, {:fetch_module, backend})

  def fetch_manifest(backend) when is_atom(backend),
    do: GenServer.call(@name, {:fetch_manifest, backend})

  def list_manifests, do: GenServer.call(@name, :list_manifests)

  @impl true
  def init(_state) do
    backends = Application.get_env(:self_hosted_inference_core, :backends, [])

    state =
      Enum.reduce(backends, %{}, fn module, acc ->
        case validate_backend(module) do
          {:ok, backend_id} -> Map.put(acc, backend_id, module)
          {:error, _reason} -> acc
        end
      end)

    {:ok, state}
  end

  @impl true
  def handle_call({:register, module}, _from, state) do
    case validate_backend(module) do
      {:ok, backend_id} ->
        {:reply, :ok, Map.put(state, backend_id, module)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:unregister, backend}, _from, state) do
    {:reply, :ok, Map.delete(state, backend)}
  end

  def handle_call({:fetch_module, backend}, _from, state) do
    case Map.fetch(state, backend) do
      {:ok, module} -> {:reply, {:ok, module}, state}
      :error -> {:reply, {:error, :backend_unregistered}, state}
    end
  end

  def handle_call({:fetch_manifest, backend}, _from, state) do
    case Map.fetch(state, backend) do
      {:ok, module} -> {:reply, {:ok, module.manifest()}, state}
      :error -> {:reply, {:error, :backend_unregistered}, state}
    end
  end

  def handle_call(:list_manifests, _from, state) do
    manifests =
      state
      |> Enum.map(fn {_backend, module} -> module.manifest() end)
      |> Enum.sort_by(& &1.backend)

    {:reply, manifests, state}
  end

  defp validate_backend(module) do
    cond do
      not Code.ensure_loaded?(module) ->
        {:error, {:backend_not_loaded, module}}

      not function_exported?(module, :backend_id, 0) ->
        {:error, {:invalid_backend, module}}

      not function_exported?(module, :manifest, 0) ->
        {:error, {:invalid_backend, module}}

      not function_exported?(module, :startup_plan, 1) ->
        {:error, {:invalid_backend, module}}

      true ->
        {:ok, module.backend_id()}
    end
  end
end
