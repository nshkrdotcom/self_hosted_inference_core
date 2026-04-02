Mix.Task.run("app.start")

defmodule SelfHostedInferenceCore.Examples.FileService do
  @moduledoc false

  def root_url_for_state_dir(state_dir) do
    "http://127.0.0.1:65535/" <> Base.url_encode64(state_dir, padding: false)
  end

  def health_status(state_dir) do
    case File.read(Path.join(state_dir, "status.txt")) do
      {:ok, "healthy"} -> {:ok, :healthy}
      {:ok, "degraded"} -> {:ok, :degraded}
      {:ok, "unavailable"} -> {:ok, :unavailable}
      {:ok, other} -> {:error, {:unexpected_status, other}}
      {:error, reason} -> {:error, reason}
    end
  end
end

defmodule SelfHostedInferenceCore.Examples.DemoBackend do
  @moduledoc false

  alias ExternalRuntimeTransport.Command

  alias SelfHostedInferenceCore.{
    Backend,
    BackendManifest,
    InstanceSpec
  }

  alias SelfHostedInferenceCore.Backend.{StartupPlan, TransportPlan}
  alias SelfHostedInferenceCore.Examples.FileService

  @behaviour Backend

  @impl Backend
  def backend_id, do: :demo_file_service

  @impl Backend
  def manifest do
    BackendManifest.new!(
      backend: backend_id(),
      runtime_kind: :service,
      management_modes: [:jido_managed],
      startup_kind: :spawned,
      protocols: [:openai_chat_completions],
      capabilities: %{streaming?: true, tool_calling?: false, embeddings?: false},
      supported_surfaces: [:local_subprocess],
      resource_profile: %{profile: :example},
      metadata: %{example: true}
    )
  end

  @impl Backend
  def startup_plan(%InstanceSpec{} = spec) do
    model_identity = Map.get(spec.backend_options, :model_identity, "demo-model")
    state_dir = state_dir_for(model_identity)

    {:ok,
     %StartupPlan{
       backend: backend_id(),
       instance_key: "demo_file_service:#{model_identity}",
       startup_kind: :spawned,
       management_mode: :jido_managed,
       transport: %TransportPlan{
         command:
           Command.new(
             System.find_executable("elixir") || "elixir",
             [script_path(), state_dir]
           ),
         execution_surface: [surface_kind: :local_subprocess],
         stdout_mode: :line,
         stdin_mode: :raw
       },
       ready_timeout_ms: 5_000,
       readiness_interval_ms: 25,
       health_interval_ms: 250,
       endpoint_template: %{
         protocol: :openai_chat_completions,
         headers: %{},
         provider_identity: :demo_file_service,
         model_identity: model_identity,
         source_runtime: __MODULE__,
         capabilities: %{streaming?: true},
         metadata: %{example: true}
       },
       backend_state: %{state_dir: nil, desired_state_dir: state_dir}
     }}
  end

  @impl Backend
  def handle_transport_event({:message, "READY " <> state_dir}, state) do
    {:pending, %{state | state_dir: String.trim(state_dir)}}
  end

  def handle_transport_event({:message, _line}, state), do: {:pending, state}
  def handle_transport_event({:stderr, _chunk}, state), do: {:pending, state}
  def handle_transport_event({:data, _chunk}, state), do: {:pending, state}
  def handle_transport_event({:exit, _exit}, state), do: {:stop, :transport_exit, state}

  @impl Backend
  def probe_readiness(%{state_dir: nil} = state), do: {:pending, state}

  def probe_readiness(%{state_dir: state_dir} = state) do
    case FileService.health_status(state_dir) do
      {:ok, _status} ->
        {:ready, endpoint_fields(state_dir), state}

      {:error, _reason} ->
        {:pending, state}
    end
  end

  @impl Backend
  def health_check(%{state_dir: nil} = state), do: {:ok, :unavailable, %{}, state}

  def health_check(%{state_dir: state_dir} = state) do
    case FileService.health_status(state_dir) do
      {:ok, status} -> {:ok, status, %{state_dir: state_dir}, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  @impl Backend
  def shutdown(%{desired_state_dir: state_dir}, _transport_pid) do
    File.rm_rf(state_dir)
    :ok
  end

  defp endpoint_fields(state_dir) do
    root_url = FileService.root_url_for_state_dir(state_dir)

    %{
      base_url: root_url <> "/v1",
      source_runtime_ref: root_url,
      health_ref: state_dir,
      boundary_ref: state_dir,
      metadata: %{state_dir: state_dir}
    }
  end

  defp script_path do
    Path.expand("support/fake_openai_service.exs", __DIR__)
  end

  defp state_dir_for(model_identity) do
    token =
      "demo_file_service:#{model_identity}"
      |> :erlang.term_to_binary()
      |> Base.url_encode64(padding: false)

    Path.join(System.tmp_dir!(), "self_hosted_inference_core_example_#{token}")
  end
end

alias SelfHostedInferenceCore.{ConsumerManifest, InstanceSpec}

:ok = SelfHostedInferenceCore.register_backend(SelfHostedInferenceCore.Examples.DemoBackend)

consumer =
  ConsumerManifest.new!(
    consumer: :jido_integration_req_llm,
    accepted_runtime_kinds: [:service],
    accepted_management_modes: [:jido_managed],
    accepted_protocols: [:openai_chat_completions],
    required_capabilities: %{streaming?: true},
    optional_capabilities: %{},
    constraints: %{},
    metadata: %{}
  )

spec =
  InstanceSpec.new!(
    backend: :demo_file_service,
    backend_options: %{model_identity: "example-model"}
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
IO.puts("First lease:        #{first.lease.lease_ref}")
IO.puts("Second lease:       #{second.lease.lease_ref}")

:ok = SelfHostedInferenceCore.release_lease(first.instance.instance_id, first.lease.lease_ref)
:ok = SelfHostedInferenceCore.release_lease(second.instance.instance_id, second.lease.lease_ref)
:ok = SelfHostedInferenceCore.stop_instance(first.instance.instance_id)
:ok = SelfHostedInferenceCore.unregister_backend(:demo_file_service)
