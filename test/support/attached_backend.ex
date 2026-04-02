defmodule SelfHostedInferenceCore.TestSupport.AttachedBackend do
  @moduledoc false

  alias SelfHostedInferenceCore.{
    Backend,
    BackendManifest,
    InstanceSpec
  }

  alias SelfHostedInferenceCore.Backend.StartupPlan
  alias SelfHostedInferenceCore.TestSupport.ExternalService

  @behaviour Backend

  @impl Backend
  def backend_id, do: :test_attached_backend

  @impl Backend
  def manifest do
    BackendManifest.new!(
      backend: backend_id(),
      runtime_kind: :service,
      management_modes: [:externally_managed],
      startup_kind: :attach_existing_service,
      protocols: [:openai_chat_completions],
      capabilities: %{
        streaming?: true,
        tool_calling?: :unknown,
        embeddings?: false
      },
      supported_surfaces: [:local_subprocess, :ssh_exec, :guest_bridge],
      resource_profile: %{profile: :attached_fixture},
      metadata: %{kind: :attached_fixture}
    )
  end

  @impl Backend
  def startup_plan(%InstanceSpec{} = spec) do
    root_url = Map.fetch!(spec.backend_options, :root_url)
    model_identity = Map.get(spec.backend_options, :model_identity, "demo-model")

    {:ok,
     %StartupPlan{
       backend: backend_id(),
       instance_key: "test_attached_backend:#{root_url}:#{model_identity}",
       startup_kind: :attach_existing_service,
       management_mode: :externally_managed,
       transport: nil,
       ready_timeout_ms: 5_000,
       readiness_interval_ms: 25,
       health_interval_ms: 50,
       endpoint_template: %{
         protocol: :openai_chat_completions,
         headers: %{},
         provider_identity: :test_attached_backend,
         model_identity: model_identity,
         source_runtime: __MODULE__,
         capabilities: %{streaming?: true},
         metadata: %{fixture: :attached}
       },
       backend_state: %{model_identity: model_identity, root_url: root_url}
     }}
  end

  @impl Backend
  def probe_readiness(%{root_url: root_url} = state) do
    case ExternalService.health_status(root_url) do
      {:ok, _status} ->
        {:ready, endpoint_fields(root_url), state}

      {:error, _reason} ->
        {:pending, state}
    end
  end

  @impl Backend
  def health_check(%{root_url: root_url} = state) do
    case ExternalService.health_status(root_url) do
      {:ok, status} ->
        {:ok, status, %{root_url: root_url}, state}

      {:error, reason} ->
        {:error, reason, state}
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
