defmodule SelfHostedInferenceCore.Simulation.Backend do
  @moduledoc false

  alias ExecutionPlane.Command

  alias SelfHostedInferenceCore.{
    BackendManifest,
    InstanceSpec
  }

  alias SelfHostedInferenceCore.Backend, as: BackendBehaviour
  alias SelfHostedInferenceCore.Backend.{StartupPlan, TransportPlan}
  alias SelfHostedInferenceCore.Simulation.Manifest

  @behaviour BackendBehaviour

  @forbidden_backend_option_keys [:boot_spec, :command, :root_url, :attach_spec]

  @impl BackendBehaviour
  def backend_id, do: :self_hosted_simulation

  @impl BackendBehaviour
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
        embeddings?: false,
        deterministic_response?: true
      },
      supported_surfaces: [:lower_simulation],
      resource_profile: %{
        scheduler: :deterministic_simulation,
        placement: :execution_plane_lower_simulation,
        gpu: :not_required
      },
      metadata: %{
        package: :self_hosted_inference_core,
        adapter: :builtin_simulation,
        side_effect_policy: :deny_process_spawn,
        manifest_contract_version: Manifest.contract_version()
      }
    )
  end

  @impl BackendBehaviour
  def startup_plan(%InstanceSpec{} = spec) do
    with :ok <- reject_real_backend_options(spec),
         :ok <- reject_execution_surface_bypass(spec),
         {:ok, %Manifest{} = manifest} <- Manifest.fetch_active() do
      manifest = Manifest.put_model_identity(manifest, requested_model_identity(spec))

      {:ok,
       %StartupPlan{
         backend: backend_id(),
         instance_key: instance_key(manifest),
         startup_kind: :spawned,
         management_mode: :jido_managed,
         transport: transport_plan(manifest, spec),
         ready_timeout_ms: manifest.ready_timeout_ms,
         readiness_interval_ms: manifest.readiness_interval_ms,
         health_interval_ms: manifest.health_interval_ms,
         endpoint_template: endpoint_template(manifest),
         backend_state: %{
           manifest: manifest,
           ready?: false,
           lower_transport_exit: nil
         },
         metadata: %{
           simulation_manifest_ref: manifest.manifest_ref,
           scenario_ref: manifest.scenario_ref,
           deterministic_response_ref: Manifest.deterministic_response_ref(manifest),
           side_effect_policy: :deny_process_spawn
         }
       }}
    end
  end

  @impl BackendBehaviour
  def handle_transport_event({:message, "READY " <> manifest_ref}, state) do
    manifest_ref = String.trim(manifest_ref)

    case state do
      %{manifest: %Manifest{manifest_ref: ^manifest_ref} = manifest} ->
        {:ready, endpoint_fields(manifest), %{state | ready?: true}}

      %{manifest: %Manifest{} = manifest} ->
        {:stop, {:simulation_manifest_ref_mismatch, manifest.manifest_ref, manifest_ref}, state}
    end
  end

  def handle_transport_event({:message, _line}, state), do: {:pending, state}
  def handle_transport_event({:stderr, _chunk}, state), do: {:pending, state}
  def handle_transport_event({:data, _chunk}, state), do: {:pending, state}

  def handle_transport_event({:exit, exit}, %{ready?: true} = state) do
    {:pending, %{state | lower_transport_exit: exit}}
  end

  def handle_transport_event({:exit, exit}, state),
    do: {:stop, {:transport_exit_before_ready, exit}, state}

  @impl BackendBehaviour
  def probe_readiness(%{ready?: true, manifest: %Manifest{} = manifest} = state) do
    {:ready, endpoint_fields(manifest), state}
  end

  def probe_readiness(state), do: {:pending, state}

  @impl BackendBehaviour
  def health_check(%{manifest: %Manifest{} = manifest} = state) do
    {:ok, manifest.health_status, health_metadata(manifest), state}
  end

  @impl BackendBehaviour
  def shutdown(_state, _transport_pid), do: :ok

  defp reject_real_backend_options(%InstanceSpec{backend_options: backend_options})
       when is_map(backend_options) do
    case Enum.find(@forbidden_backend_option_keys, &has_option?(backend_options, &1)) do
      nil -> :ok
      key -> {:error, {:simulation_backend_bypass_denied, key}}
    end
  end

  defp reject_real_backend_options(%InstanceSpec{}), do: :ok

  defp reject_execution_surface_bypass(%InstanceSpec{execution_surface: nil}), do: :ok

  defp reject_execution_surface_bypass(%InstanceSpec{execution_surface: execution_surface}) do
    case execution_surface_kind(execution_surface) do
      :lower_simulation ->
        :ok

      surface_kind ->
        {:error, {:simulation_backend_bypass_denied, {:execution_surface, surface_kind}}}
    end
  end

  defp transport_plan(%Manifest{} = manifest, %InstanceSpec{} = spec) do
    %TransportPlan{
      command:
        Command.new("self-hosted-simulation-backend-must-not-exist", [
          "--manifest-ref",
          manifest.manifest_ref
        ]),
      execution_surface: [
        surface_kind: :lower_simulation,
        target_id: "self-hosted-simulation",
        surface_ref: manifest.endpoint_ref,
        boundary_class: :self_hosted_inference,
        observability: observability(spec),
        transport_options: [
          scenario_ref: manifest.scenario_ref,
          stdout_frames: ["READY #{manifest.manifest_ref}\n"],
          stderr_frames: [],
          exit: :normal
        ]
      ],
      stdout_mode: :line,
      stdin_mode: :raw
    }
  end

  defp endpoint_template(%Manifest{} = manifest) do
    %{
      protocol: manifest.protocol,
      headers: manifest.headers,
      provider_identity: manifest.provider_identity,
      model_identity: manifest.model_identity,
      source_runtime: backend_id(),
      source_runtime_ref: manifest.manifest_ref,
      capabilities: manifest.capabilities,
      metadata:
        Map.merge(manifest.metadata, %{
          simulation_manifest_ref: manifest.manifest_ref,
          scenario_ref: manifest.scenario_ref,
          deterministic_response_ref: Manifest.deterministic_response_ref(manifest),
          deterministic_response: manifest.deterministic_response,
          side_effect_policy: :deny_process_spawn
        })
    }
  end

  defp endpoint_fields(%Manifest{} = manifest) do
    %{
      base_url: manifest.base_url,
      source_runtime_ref: manifest.manifest_ref,
      health_ref: "self-hosted-simulation://health/#{manifest.manifest_ref}",
      boundary_ref: manifest.endpoint_ref,
      metadata:
        Map.merge(manifest.metadata, %{
          simulation_manifest_ref: manifest.manifest_ref,
          scenario_ref: manifest.scenario_ref,
          deterministic_response_ref: Manifest.deterministic_response_ref(manifest),
          deterministic_response: manifest.deterministic_response,
          side_effect_policy: :deny_process_spawn
        })
    }
  end

  defp health_metadata(%Manifest{} = manifest) do
    %{
      simulation_manifest_ref: manifest.manifest_ref,
      scenario_ref: manifest.scenario_ref,
      deterministic_response_ref: Manifest.deterministic_response_ref(manifest)
    }
  end

  defp instance_key(%Manifest{} = manifest) do
    "self_hosted_simulation:#{manifest.manifest_ref}:#{manifest.model_identity}"
  end

  defp requested_model_identity(%InstanceSpec{backend_options: backend_options})
       when is_map(backend_options) do
    get_option(backend_options, :model_identity)
  end

  defp requested_model_identity(%InstanceSpec{}), do: nil

  defp observability(%InstanceSpec{metadata: metadata}) when is_map(metadata) do
    metadata
    |> Map.take([:request_id, :run_id, :attempt_id, :boundary_ref, :trace_id])
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp observability(%InstanceSpec{}), do: %{}

  defp has_option?(map, key), do: Map.has_key?(map, key) or Map.has_key?(map, Atom.to_string(key))

  defp get_option(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp execution_surface_kind(surface) when is_list(surface) do
    surface
    |> Keyword.get(:surface_kind, :local_subprocess)
    |> normalize_surface_kind()
  end

  defp execution_surface_kind(%ExecutionPlane.Placements.Surface{surface_kind: surface_kind}) do
    normalize_surface_kind(surface_kind)
  end

  defp execution_surface_kind(surface) when is_map(surface) do
    surface
    |> Map.get(:surface_kind, Map.get(surface, "surface_kind", :local_subprocess))
    |> normalize_surface_kind()
  end

  defp execution_surface_kind(_surface), do: :local_subprocess

  defp normalize_surface_kind("lower_simulation"), do: :lower_simulation
  defp normalize_surface_kind(surface_kind) when is_atom(surface_kind), do: surface_kind
  defp normalize_surface_kind(_surface_kind), do: :local_subprocess
end
