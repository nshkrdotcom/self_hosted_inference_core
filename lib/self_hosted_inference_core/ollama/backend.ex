defmodule SelfHostedInferenceCore.Ollama.Backend do
  @moduledoc false

  alias SelfHostedInferenceCore.Backend, as: BackendBehaviour
  alias SelfHostedInferenceCore.Backend.StartupPlan
  alias SelfHostedInferenceCore.{BackendManifest, InstanceSpec}
  alias SelfHostedInferenceCore.Ollama.{AttachSpec, HTTP}

  @behaviour BackendBehaviour

  @impl BackendBehaviour
  def backend_id, do: :ollama

  @impl BackendBehaviour
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
        embeddings?: :unknown
      },
      supported_surfaces: [:local_subprocess],
      resource_profile: %{
        scheduler: :externally_managed,
        placement: :existing_service,
        gpu: :provider_managed
      },
      metadata: %{
        package: :self_hosted_inference_core,
        adapter: :builtin,
        vllm: :future_additive
      }
    )
  end

  @impl BackendBehaviour
  def startup_plan(%InstanceSpec{} = spec) do
    with {:ok, %AttachSpec{} = attach_spec} <- attach_spec_from_instance_spec(spec) do
      {:ok,
       %StartupPlan{
         backend: backend_id(),
         instance_key: AttachSpec.instance_key(attach_spec),
         startup_kind: :attach_existing_service,
         management_mode: :externally_managed,
         transport: nil,
         ready_timeout_ms: attach_spec.ready_timeout_ms,
         readiness_interval_ms: attach_spec.readiness_interval_ms,
         health_interval_ms: attach_spec.health_interval_ms,
         endpoint_template: %{
           protocol: :openai_chat_completions,
           headers: attach_spec.headers,
           provider_identity: :ollama,
           model_identity: attach_spec.model_identity,
           source_runtime: :ollama,
           capabilities: %{
             streaming?: true,
             tool_calling?: :unknown,
             embeddings?: :unknown
           },
           metadata: endpoint_metadata(attach_spec)
         },
         backend_state: %{
           attach_spec: attach_spec,
           version: nil,
           running_models: []
         },
         metadata: %{attach_spec: endpoint_metadata(attach_spec)}
       }}
    end
  end

  @impl BackendBehaviour
  def probe_readiness(%{attach_spec: %AttachSpec{} = attach_spec} = state) do
    case readiness_probe(attach_spec) do
      {:ready, version} ->
        {:ready, endpoint_fields(attach_spec, version), %{state | version: version}}

      :pending ->
        {:pending, state}
    end
  end

  @impl BackendBehaviour
  def health_check(%{attach_spec: %AttachSpec{} = attach_spec} = state) do
    timeout_ms = min(attach_spec.health_interval_ms, 5_000)

    with {:ok, version} <-
           HTTP.fetch_version(
             attach_spec.root_url,
             timeout_ms: timeout_ms,
             ollama_http: attach_spec.ollama_http
           ),
         {:ok, _details} <-
           HTTP.show_model(
             attach_spec.root_url,
             attach_spec.model_identity,
             timeout_ms: timeout_ms,
             ollama_http: attach_spec.ollama_http
           ),
         {:ok, running_models} <-
           HTTP.running_models(
             attach_spec.root_url,
             timeout_ms: timeout_ms,
             ollama_http: attach_spec.ollama_http
           ) do
      running_names =
        Enum.map(running_models, fn model ->
          Map.get(model, "name", Map.get(model, :name))
        end)

      health_status =
        if attach_spec.model_identity in running_names do
          :healthy
        else
          :degraded
        end

      {:ok, health_status,
       %{version: version, running_models: running_names, root_url: attach_spec.root_url},
       %{state | version: version, running_models: running_names}}
    else
      {:error, reason} ->
        {:error, reason, state}
    end
  end

  @impl BackendBehaviour
  def shutdown(_state, _transport_pid), do: :ok

  defp attach_spec_from_instance_spec(%InstanceSpec{
         backend_options: %{attach_spec: %AttachSpec{} = attach_spec}
       }) do
    {:ok, attach_spec}
  end

  defp attach_spec_from_instance_spec(%InstanceSpec{
         backend_options: %{attach_spec: attrs},
         execution_surface: execution_surface
       })
       when is_map(attrs) or is_list(attrs) do
    attrs
    |> Map.new()
    |> Map.put_new(:execution_surface, execution_surface)
    |> AttachSpec.new()
  end

  defp attach_spec_from_instance_spec(%InstanceSpec{
         backend_options: backend_options,
         execution_surface: execution_surface
       })
       when is_map(backend_options) do
    backend_options
    |> Map.put_new(:execution_surface, execution_surface)
    |> AttachSpec.new()
  end

  defp readiness_probe(%AttachSpec{} = attach_spec) do
    timeout_ms = min(attach_spec.ready_timeout_ms, 5_000)

    with {:ok, version} <-
           HTTP.fetch_version(
             attach_spec.root_url,
             timeout_ms: timeout_ms,
             ollama_http: attach_spec.ollama_http
           ),
         {:ok, _details} <-
           HTTP.show_model(
             attach_spec.root_url,
             attach_spec.model_identity,
             timeout_ms: timeout_ms,
             ollama_http: attach_spec.ollama_http
           ) do
      {:ready, version}
    else
      {:error, {:http_error, 404, _body}} -> :pending
      {:error, _reason} -> :pending
    end
  end

  defp endpoint_fields(%AttachSpec{} = attach_spec, version) do
    %{
      base_url: AttachSpec.base_url(attach_spec),
      source_runtime_ref: attach_spec.root_url,
      health_ref: AttachSpec.health_url(attach_spec),
      boundary_ref: boundary_ref(attach_spec.execution_surface),
      metadata:
        Map.merge(endpoint_metadata(attach_spec), %{
          ollama_version: version
        })
    }
  end

  defp endpoint_metadata(%AttachSpec{} = attach_spec) do
    %{
      root_url: attach_spec.root_url,
      execution_surface: surface_kind(attach_spec.execution_surface)
    }
    |> Map.merge(Map.new(attach_spec.metadata))
  end

  defp boundary_ref(%ExecutionPlane.Placements.Surface{} = surface) do
    surface.surface_ref || surface.target_id
  end

  defp boundary_ref(surface) when is_list(surface) do
    Keyword.get(surface, :surface_ref) || Keyword.get(surface, :target_id)
  end

  defp boundary_ref(surface) when is_map(surface) do
    Map.get(surface, :surface_ref, Map.get(surface, "surface_ref")) ||
      Map.get(surface, :target_id, Map.get(surface, "target_id"))
  end

  defp boundary_ref(_surface), do: nil

  defp surface_kind(%ExecutionPlane.Placements.Surface{} = surface),
    do: normalize_surface_kind(surface.surface_kind)

  defp surface_kind(surface) when is_list(surface),
    do: normalize_surface_kind(Keyword.get(surface, :surface_kind, :local_subprocess))

  defp surface_kind(surface) when is_map(surface) do
    surface
    |> Map.get(:surface_kind, Map.get(surface, "surface_kind", :local_subprocess))
    |> normalize_surface_kind()
  end

  defp surface_kind(_surface), do: :local_subprocess

  defp normalize_surface_kind("local_subprocess"), do: :local_subprocess
  defp normalize_surface_kind("ssh_exec"), do: :ssh_exec
  defp normalize_surface_kind("guest_bridge"), do: :guest_bridge
  defp normalize_surface_kind(surface_kind) when is_atom(surface_kind), do: surface_kind
  defp normalize_surface_kind(_surface_kind), do: :local_subprocess
end
