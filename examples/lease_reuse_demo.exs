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

alias SelfHostedInferenceCore.ConsumerManifest

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

request = %{
  request_id: "req-self-hosted-example-1",
  target_preference: %{
    target_class: "self_hosted_endpoint",
    backend: "demo_file_service",
    backend_options: %{model_identity: "example-model"}
  }
}

first_context = %{
  run_id: "run-self-hosted-example-1",
  attempt_id: "run-self-hosted-example-1:1",
  boundary_ref: "boundary-self-hosted-example-1",
  observability: %{trace_id: "trace-self-hosted-example-1"}
}

second_context = %{
  run_id: "run-self-hosted-example-1",
  attempt_id: "run-self-hosted-example-1:2",
  boundary_ref: "boundary-self-hosted-example-1",
  observability: %{trace_id: "trace-self-hosted-example-2"}
}

{:ok, first_endpoint, first_compatibility} =
  SelfHostedInferenceCore.ensure_endpoint(
    request,
    consumer,
    first_context,
    owner_ref: "example-owner-a",
    ttl_ms: 30_000
  )

{:ok, second_endpoint, second_compatibility} =
  SelfHostedInferenceCore.ensure_endpoint(
    request,
    consumer,
    second_context,
    owner_ref: "example-owner-b",
    ttl_ms: 30_000
  )

IO.puts("First endpoint:     #{first_endpoint.base_url}")
IO.puts("Second endpoint:    #{second_endpoint.base_url}")

IO.puts(
  "Same endpoint?:     #{inspect(first_endpoint.endpoint_id == second_endpoint.endpoint_id)}"
)

IO.puts("First lease ref:    #{first_endpoint.lease_ref}")
IO.puts("Second lease ref:   #{second_endpoint.lease_ref}")
IO.puts("First compatibility #{inspect(first_compatibility.reason)}")
IO.puts("Second compatibility #{inspect(second_compatibility.reason)}")

:ok = SelfHostedInferenceCore.stop_all_instances()
:ok = SelfHostedInferenceCore.unregister_backend(:demo_file_service)
