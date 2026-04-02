Mix.Task.run("app.start")

defmodule SelfHostedInferenceCore.Examples.AttachedService do
  @moduledoc false

  defstruct [:port, :root_url, :state_dir]

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
        {:error, reason} -> raise "failed to start attached example service: #{inspect(reason)}"
      end

    %__MODULE__{
      port: port,
      state_dir: ready_state_dir,
      root_url: root_url_for_state_dir(ready_state_dir)
    }
  end

  def stop(%__MODULE__{} = service) do
    if Port.info(service.port) do
      Port.close(service.port)
    end

    File.rm_rf(service.state_dir)
    :ok
  rescue
    ArgumentError -> :ok
  end

  def alive?(%__MODULE__{} = service), do: Port.info(service.port) != nil

  def health_status(root_url) when is_binary(root_url) do
    case File.read(root_url |> state_dir_from_root_url() |> Path.join("status.txt")) do
      {:ok, "healthy"} -> {:ok, :healthy}
      {:ok, "degraded"} -> {:ok, :degraded}
      {:ok, "unavailable"} -> {:ok, :unavailable}
      {:ok, other} -> {:error, {:unexpected_status, other}}
      {:error, reason} -> {:error, reason}
    end
  end

  def root_url_for_state_dir(state_dir) do
    "http://127.0.0.1:65535/" <> Base.url_encode64(state_dir, padding: false)
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

  defp state_dir_from_root_url(root_url) do
    root_url
    |> String.split("/", parts: 4)
    |> List.last()
    |> Base.url_decode64!(padding: false)
  end

  defp script_path do
    Path.expand("support/fake_openai_service.exs", __DIR__)
  end

  defp unique_state_dir do
    Path.join(
      System.tmp_dir!(),
      "self_hosted_inference_core_attached_example_#{System.unique_integer([:positive, :monotonic])}"
    )
  end
end

defmodule SelfHostedInferenceCore.Examples.DemoAttachedBackend do
  @moduledoc false

  alias SelfHostedInferenceCore.{
    Backend,
    BackendManifest,
    InstanceSpec
  }

  alias SelfHostedInferenceCore.Backend.StartupPlan
  alias SelfHostedInferenceCore.Examples.AttachedService

  @behaviour Backend

  @impl Backend
  def backend_id, do: :demo_attached_service

  @impl Backend
  def manifest do
    BackendManifest.new!(
      backend: backend_id(),
      runtime_kind: :service,
      management_modes: [:externally_managed],
      startup_kind: :attach_existing_service,
      protocols: [:openai_chat_completions],
      capabilities: %{streaming?: true, tool_calling?: :unknown, embeddings?: false},
      supported_surfaces: [:local_subprocess, :ssh_exec, :guest_bridge],
      resource_profile: %{profile: :example},
      metadata: %{example: true}
    )
  end

  @impl Backend
  def startup_plan(%InstanceSpec{} = spec) do
    root_url = Map.fetch!(spec.backend_options, :root_url)
    model_identity = Map.get(spec.backend_options, :model_identity, "demo-model")

    {:ok,
     %StartupPlan{
       backend: backend_id(),
       instance_key: "demo_attached_service:#{root_url}:#{model_identity}",
       startup_kind: :attach_existing_service,
       management_mode: :externally_managed,
       transport: nil,
       ready_timeout_ms: 5_000,
       readiness_interval_ms: 25,
       health_interval_ms: 250,
       endpoint_template: %{
         protocol: :openai_chat_completions,
         headers: %{},
         provider_identity: :demo_attached_service,
         model_identity: model_identity,
         source_runtime: __MODULE__,
         capabilities: %{streaming?: true},
         metadata: %{example: true}
       },
       backend_state: %{root_url: root_url, model_identity: model_identity}
     }}
  end

  @impl Backend
  def probe_readiness(%{root_url: root_url} = state) do
    case AttachedService.health_status(root_url) do
      {:ok, _status} ->
        {:ready, endpoint_fields(root_url), state}

      {:error, _reason} ->
        {:pending, state}
    end
  end

  @impl Backend
  def health_check(%{root_url: root_url} = state) do
    case AttachedService.health_status(root_url) do
      {:ok, status} -> {:ok, status, %{root_url: root_url}, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  @impl Backend
  def shutdown(_state, _transport_pid), do: :ok

  defp endpoint_fields(root_url) do
    %{
      base_url: root_url <> "/v1",
      source_runtime_ref: root_url,
      health_ref: root_url <> "/health",
      metadata: %{root_url: root_url}
    }
  end
end

alias SelfHostedInferenceCore.{ConsumerManifest, InstanceSpec}
alias SelfHostedInferenceCore.Examples.AttachedService

service = AttachedService.start!()

try do
  :ok =
    SelfHostedInferenceCore.register_backend(SelfHostedInferenceCore.Examples.DemoAttachedBackend)

  consumer =
    ConsumerManifest.new!(
      consumer: :jido_integration_req_llm,
      accepted_runtime_kinds: [:service],
      accepted_management_modes: [:externally_managed],
      accepted_protocols: [:openai_chat_completions],
      required_capabilities: %{streaming?: true},
      optional_capabilities: %{},
      constraints: %{},
      metadata: %{}
    )

  spec =
    InstanceSpec.new!(
      backend: :demo_attached_service,
      startup_kind: :attach_existing_service,
      backend_options: %{
        model_identity: "example-model",
        root_url: service.root_url
      }
    )

  {:ok, first} =
    SelfHostedInferenceCore.resolve_endpoint(
      spec,
      consumer,
      owner_ref: "example-owner-a",
      ttl_ms: 30_000
    )

  {:ok, second} =
    SelfHostedInferenceCore.resolve_endpoint(
      spec,
      consumer,
      owner_ref: "example-owner-b",
      ttl_ms: 30_000
    )

  IO.puts("First instance id:  #{first.instance.instance_id}")
  IO.puts("Second instance id: #{second.instance.instance_id}")
  IO.puts("Endpoint:           #{first.endpoint.base_url}")
  IO.puts("Reused instance?:   #{inspect(second.reused?)}")
  IO.puts("Management mode:    #{inspect(first.endpoint.management_mode)}")
  IO.puts("Service alive pre-stop?:  #{inspect(AttachedService.alive?(service))}")

  :ok = SelfHostedInferenceCore.stop_instance(first.instance.instance_id)

  IO.puts("Service alive post-stop?: #{inspect(AttachedService.alive?(service))}")

  :ok = SelfHostedInferenceCore.release_lease(first.instance.instance_id, first.lease.lease_ref)
  :ok = SelfHostedInferenceCore.release_lease(second.instance.instance_id, second.lease.lease_ref)
  :ok = SelfHostedInferenceCore.unregister_backend(:demo_attached_service)
after
  AttachedService.stop(service)
end
