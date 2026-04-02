defmodule SelfHostedInferenceCore.TestSupport.SpawnedBackend do
  @moduledoc false

  alias ExternalRuntimeTransport.Command

  alias SelfHostedInferenceCore.{
    Backend,
    BackendManifest,
    InstanceSpec
  }

  alias SelfHostedInferenceCore.Backend.{StartupPlan, TransportPlan}
  alias SelfHostedInferenceCore.TestSupport.ExternalService

  @behaviour Backend

  @impl Backend
  def backend_id, do: :test_spawned_backend

  @impl Backend
  def manifest do
    BackendManifest.new!(
      backend: backend_id(),
      runtime_kind: :service,
      management_modes: [:jido_managed],
      startup_kind: :spawned,
      protocols: [:openai_chat_completions],
      capabilities: %{
        streaming?: true,
        tool_calling?: false,
        embeddings?: false
      },
      supported_surfaces: [:local_subprocess],
      resource_profile: %{profile: :test_fixture},
      metadata: %{kind: :spawned_fixture}
    )
  end

  @impl Backend
  def startup_plan(%InstanceSpec{} = spec) do
    model_identity = Map.get(spec.backend_options, :model_identity, "demo-model")
    state_dir = state_dir_for(model_identity)

    transport =
      %TransportPlan{
        command:
          Command.new(
            System.find_executable("elixir") || "elixir",
            [script_path(), state_dir]
          ),
        execution_surface:
          spec.execution_surface ||
            [
              surface_kind: :local_subprocess
            ],
        stdout_mode: :line,
        stdin_mode: :raw
      }

    {:ok,
     %StartupPlan{
       backend: backend_id(),
       instance_key: "test_spawned_backend:#{model_identity}",
       startup_kind: :spawned,
       management_mode: :jido_managed,
       transport: transport,
       ready_timeout_ms: 5_000,
       readiness_interval_ms: 25,
       health_interval_ms: 50,
       endpoint_template: %{
         protocol: :openai_chat_completions,
         headers: %{},
         provider_identity: :test_spawned_backend,
         model_identity: model_identity,
         source_runtime: __MODULE__,
         capabilities: %{streaming?: true},
         metadata: %{fixture: :spawned}
       },
       backend_state: %{
         model_identity: model_identity,
         state_dir: nil,
         desired_state_dir: state_dir
       }
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
    case ExternalService.health_status(ExternalService.root_url_for_state_dir(state_dir)) do
      {:ok, _status} ->
        {:ready, endpoint_fields(state_dir), state}

      {:error, _reason} ->
        {:pending, state}
    end
  end

  @impl Backend
  def health_check(%{state_dir: nil} = state), do: {:ok, :unavailable, %{}, state}

  def health_check(%{state_dir: state_dir} = state) do
    root_url = ExternalService.root_url_for_state_dir(state_dir)

    case ExternalService.health_status(root_url) do
      {:ok, status} ->
        {:ok, status, %{state_dir: state_dir}, state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  @impl Backend
  def shutdown(%{desired_state_dir: state_dir}, _transport_pid) do
    File.rm_rf(state_dir)
    :ok
  end

  defp endpoint_fields(state_dir) do
    root_url = ExternalService.root_url_for_state_dir(state_dir)

    %{
      base_url: root_url <> "/v1",
      source_runtime_ref: root_url,
      health_ref: state_dir,
      boundary_ref: state_dir,
      metadata: %{state_dir: state_dir}
    }
  end

  defp script_path do
    Path.expand("fixtures/fake_openai_service.exs", __DIR__)
  end

  defp state_dir_for(model_identity) do
    token =
      "test_spawned_backend:#{model_identity}"
      |> :erlang.term_to_binary()
      |> Base.url_encode64(padding: false)

    Path.join(System.tmp_dir!(), "self_hosted_inference_core_spawned_#{token}")
  end
end
