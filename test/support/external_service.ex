defmodule SelfHostedInferenceCore.TestSupport.ExternalService do
  @moduledoc false

  defstruct [:port, :root_url, :state_dir]

  @type t :: %__MODULE__{
          port: port(),
          root_url: String.t(),
          state_dir: String.t()
        }

  @spec start!() :: t()
  def start! do
    executable = System.find_executable("elixir") || raise "elixir executable not found"
    state_dir = unique_state_dir()

    port =
      Port.open(
        {:spawn_executable, executable},
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          args: [script_path(), state_dir]
        ]
      )

    ready_state_dir =
      case await_ready(port, "") do
        {:ok, value} -> value
        {:error, reason} -> raise "failed to start external service: #{inspect(reason)}"
      end

    %__MODULE__{
      port: port,
      state_dir: ready_state_dir,
      root_url: synthetic_root_url(ready_state_dir)
    }
  end

  @spec stop(t()) :: :ok
  def stop(%__MODULE__{} = service) do
    if Port.info(service.port) do
      Port.close(service.port)
    end

    File.rm_rf(service.state_dir)
    :ok
  rescue
    ArgumentError -> :ok
  end

  @spec alive?(t()) :: boolean()
  def alive?(%__MODULE__{} = service) do
    Port.info(service.port) != nil
  end

  @spec set_health(t() | String.t(), :healthy | :degraded | :unavailable) ::
          :ok | {:error, term()}
  def set_health(service_or_url, status) when status in [:healthy, :degraded, :unavailable] do
    service_or_url
    |> state_dir()
    |> Path.join("status.txt")
    |> File.write(Atom.to_string(status))
  end

  @spec health_status(t() | String.t()) ::
          {:ok, :healthy | :degraded | :unavailable} | {:error, term()}
  def health_status(service_or_url) do
    case service_or_url |> state_dir() |> Path.join("status.txt") |> File.read() do
      {:ok, "healthy"} -> {:ok, :healthy}
      {:ok, "degraded"} -> {:ok, :degraded}
      {:ok, "unavailable"} -> {:ok, :unavailable}
      {:ok, other} -> {:error, {:unexpected_status, other}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec root_url(t() | String.t()) :: String.t()
  def root_url(%__MODULE__{root_url: root_url}), do: root_url

  def root_url(url) when is_binary(url) do
    String.replace_suffix(url, "/v1", "")
  end

  @spec root_url_for_state_dir(String.t()) :: String.t()
  def root_url_for_state_dir(state_dir) when is_binary(state_dir) do
    synthetic_root_url(state_dir)
  end

  defp await_ready(port, buffer, attempts \\ 200)

  defp await_ready(_port, _buffer, 0), do: {:error, :timeout}

  defp await_ready(port, buffer, attempts) do
    receive do
      {^port, {:data, data}} ->
        next_buffer = buffer <> data

        case Regex.run(~r/READY\s+([^\n\r]+)/, next_buffer) do
          [_, state_dir] -> {:ok, String.trim(state_dir)}
          _no_match -> await_ready(port, next_buffer, attempts - 1)
        end

      {^port, {:exit_status, status}} ->
        {:error, {:exit_status, status, buffer}}
    after
      50 ->
        await_ready(port, buffer, attempts - 1)
    end
  end

  defp script_path do
    Path.expand("fixtures/fake_openai_service.exs", __DIR__)
  end

  defp state_dir(%__MODULE__{state_dir: state_dir}), do: state_dir

  defp state_dir(url) when is_binary(url) do
    url
    |> root_url()
    |> String.split("/", parts: 4)
    |> List.last()
    |> Base.url_decode64!(padding: false)
  end

  defp synthetic_root_url(state_dir) do
    "http://127.0.0.1:65535/" <> Base.url_encode64(state_dir, padding: false)
  end

  defp unique_state_dir do
    Path.join(
      System.tmp_dir!(),
      "self_hosted_inference_core_fixture_#{System.unique_integer([:positive, :monotonic])}"
    )
  end
end
