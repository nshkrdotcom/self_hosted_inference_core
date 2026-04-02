defmodule SelfHostedInferenceCore.TestSupport.OllamaService do
  @moduledoc false

  defstruct [:pid, :root_url]

  @type t :: %__MODULE__{
          pid: pid(),
          root_url: String.t()
        }

  @spec start!(keyword()) :: t()
  def start!(opts \\ []) do
    {:ok, pid} =
      Agent.start_link(fn ->
        %{
          installed_models: Keyword.get(opts, :installed_models, []),
          running_models: Keyword.get(opts, :running_models, []),
          version: Keyword.get(opts, :version, "0.0.0"),
          response_text: Keyword.get(opts, :response_text, "Ollama attach path is alive.")
        }
      end)

    %__MODULE__{
      pid: pid,
      root_url: "http://ollama.test/#{System.unique_integer([:positive, :monotonic])}"
    }
  end

  @spec stop(t()) :: :ok
  def stop(%__MODULE__{} = service) do
    if Process.alive?(service.pid) do
      Agent.stop(service.pid, :normal)
    end

    :ok
  catch
    :exit, _reason -> :ok
  end

  @spec alive?(t()) :: boolean()
  def alive?(%__MODULE__{} = service), do: Process.alive?(service.pid)

  @spec set_installed_models(t(), [String.t()]) :: :ok | {:error, term()}
  def set_installed_models(%__MODULE__{pid: pid}, models) when is_list(models) do
    Agent.update(pid, &Map.put(&1, :installed_models, normalize_models(models)))
  end

  @spec set_running_models(t(), [String.t()]) :: :ok | {:error, term()}
  def set_running_models(%__MODULE__{pid: pid}, models) when is_list(models) do
    Agent.update(pid, &Map.put(&1, :running_models, normalize_models(models)))
  end

  @spec http_stub(t()) ::
          (atom(), String.t(), map() | nil, keyword() ->
             {:ok, pos_integer(), map()} | {:error, term()})
  def http_stub(%__MODULE__{} = service) do
    fn method, path, payload, _opts ->
      handle_request(service, method, path, payload)
    end
  end

  defp handle_request(%__MODULE__{pid: pid}, :get, "/api/version", _payload) do
    version = Agent.get(pid, & &1.version)
    {:ok, 200, %{"version" => version}}
  end

  defp handle_request(%__MODULE__{pid: pid}, :get, "/api/ps", _payload) do
    running_models = Agent.get(pid, & &1.running_models)
    {:ok, 200, %{"models" => Enum.map(running_models, &%{"name" => &1})}}
  end

  defp handle_request(%__MODULE__{pid: pid}, :post, "/api/show", %{"model" => model}) do
    installed_models = Agent.get(pid, & &1.installed_models)

    if model in installed_models do
      {:ok, 200, %{"model" => model, "details" => %{"family" => "llama"}}}
    else
      {:ok, 404, %{"error" => "model not found"}}
    end
  end

  defp handle_request(_service, method, path, _payload)
       when method in [:get, :post] and path in ["/api/tags", "/v1/chat/completions"] do
    {:error, {:unsupported_stub_endpoint, method, path}}
  end

  defp handle_request(_service, method, path, _payload),
    do: {:error, {:unexpected_request, method, path}}

  defp normalize_models(models) do
    models
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
