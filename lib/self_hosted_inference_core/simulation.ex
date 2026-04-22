defmodule SelfHostedInferenceCore.Simulation do
  @moduledoc """
  Built-in configured backend for service-mode self-hosted inference simulation.

  This backend is selected by registering `SelfHostedInferenceCore.Simulation`
  and installing a `:simulation_backend` application configuration. It uses
  Execution Plane's `:lower_simulation` process transport and never launches a
  real backend process.
  """

  alias SelfHostedInferenceCore.{
    AdapterSelectionPolicy,
    BackendManifest,
    ConsumerManifest,
    InstanceSpec,
    LowerSimulationScenario
  }

  alias SelfHostedInferenceCore.Simulation.{Backend, Manifest}

  @type metadata :: %{
          app: atom(),
          backend: atom(),
          version: String.t()
        }

  @spec metadata() :: metadata()
  def metadata do
    %{
      app: :self_hosted_inference_core,
      backend: backend_id(),
      version: to_string(Application.spec(:self_hosted_inference_core, :vsn))
    }
  end

  @spec backend_id() :: :self_hosted_simulation
  def backend_id, do: :self_hosted_simulation

  @doc """
  Declares the Phase 6 adapter selection policy for self-hosted simulation.
  """
  @spec adapter_selection_policy() :: AdapterSelectionPolicy.t()
  def adapter_selection_policy do
    AdapterSelectionPolicy.new!(%{
      selection_surface: "backend_manifest",
      owner_repo: "self_hosted_inference_core",
      config_key: "self_hosted_inference_core.simulation_backend",
      default_value_when_unset: "real_backend_registry",
      fail_closed_action_when_misconfigured: "reject_required_or_invalid_manifest"
    })
  end

  @doc """
  Builds the owner-local Phase 6 lower scenario declaration for a self-hosted manifest.
  """
  @spec lower_simulation_scenario!(String.t(), map() | keyword()) ::
          LowerSimulationScenario.t()
  def lower_simulation_scenario!(scenario_ref, overrides \\ []) when is_binary(scenario_ref) do
    overrides = normalize_overrides!(overrides)

    %{
      scenario_id: scenario_ref,
      version: "1.0.0",
      owner_repo: "self_hosted_inference_core",
      route_kind: "self_hosted_backend_manifest",
      protocol_surface: "self_hosted",
      matcher_class: "deterministic_over_input",
      status_or_exit_or_response_or_stream_or_chunk_or_fault_shape: %{
        "ready_frame" => "configured",
        "endpoint_descriptor" => "configured",
        "health_status" => "configured",
        "deterministic_response_shape" => "configured"
      },
      no_egress_assertion: %{
        "external_egress" => "deny",
        "process_spawn" => "deny",
        "side_effect_result" => "not_attempted"
      },
      bounded_evidence_projection: %{
        "contract_version" => "ExecutionPlane.LowerSimulationEvidence.v1",
        "raw_payload_persistence" => "shape_only",
        "fingerprints" => ["manifest", "endpoint_shape", "response_shape"]
      },
      input_fingerprint_ref: "fingerprint://self-hosted-inference/lower-simulation/input",
      cleanup_behavior: %{
        "runtime_artifacts" => "delete",
        "durable_payload" => "deny_raw"
      }
    }
    |> Map.merge(overrides)
    |> LowerSimulationScenario.new!()
  end

  @spec register_backend() :: :ok | {:error, term()}
  def register_backend do
    SelfHostedInferenceCore.register_backend(Backend)
  end

  @spec unregister_backend() :: :ok
  def unregister_backend do
    SelfHostedInferenceCore.unregister_backend(backend_id())
  end

  @spec manifest() :: BackendManifest.t()
  def manifest, do: Backend.manifest()

  @spec active_manifest() :: {:ok, Manifest.t()} | {:error, term()}
  def active_manifest, do: Manifest.fetch_active()

  @spec instance_spec(keyword() | map()) :: {:ok, InstanceSpec.t()} | {:error, term()}
  def instance_spec(attrs \\ []) when is_list(attrs) or is_map(attrs) do
    with :ok <- reject_public_simulation_selector(attrs) do
      attrs = Map.new(attrs)

      InstanceSpec.new(
        backend: backend_id(),
        startup_kind: :spawned,
        execution_surface:
          Map.get(attrs, :execution_surface, Map.get(attrs, "execution_surface")),
        backend_options: Map.get(attrs, :backend_options, Map.get(attrs, "backend_options", %{})),
        metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
      )
    end
  end

  @spec ensure_instance(keyword() | map(), keyword()) ::
          {:ok, SelfHostedInferenceCore.ensure_result()} | {:error, term()}
  def ensure_instance(attrs \\ [], opts \\ []) do
    with :ok <- reject_public_simulation_selector(opts),
         {:ok, %InstanceSpec{} = instance_spec} <- instance_spec(attrs) do
      SelfHostedInferenceCore.ensure_instance(instance_spec, opts)
    end
  end

  @spec resolve_endpoint(keyword() | map(), ConsumerManifest.t(), keyword()) ::
          {:ok, SelfHostedInferenceCore.resolve_result()} | {:error, term()}
  def resolve_endpoint(attrs, %ConsumerManifest{} = consumer_manifest, opts \\ []) do
    with :ok <- reject_public_simulation_selector(opts),
         {:ok, %InstanceSpec{} = instance_spec} <- instance_spec(attrs) do
      SelfHostedInferenceCore.resolve_endpoint(instance_spec, consumer_manifest, opts)
    end
  end

  @spec compatibility(ConsumerManifest.t()) :: SelfHostedInferenceCore.CompatibilityResult.t()
  def compatibility(%ConsumerManifest{} = consumer_manifest) do
    SelfHostedInferenceCore.compatibility(backend_id(), consumer_manifest)
  end

  defp normalize_overrides!(overrides) when is_map(overrides), do: overrides

  defp normalize_overrides!(overrides) when is_list(overrides) do
    if Keyword.keyword?(overrides) do
      Map.new(overrides)
    else
      raise ArgumentError, "expected keyword overrides, got: #{inspect(overrides)}"
    end
  end

  defp normalize_overrides!(overrides) do
    raise ArgumentError, "expected map or keyword overrides, got: #{inspect(overrides)}"
  end

  defp reject_public_simulation_selector(values) when is_list(values) do
    if Enum.any?(values, &public_simulation_entry?/1) do
      {:error, {:public_simulation_selector_forbidden, :self_hosted_inference_core}}
    else
      :ok
    end
  end

  defp reject_public_simulation_selector(values) when is_map(values) do
    if Map.has_key?(values, :simulation) or Map.has_key?(values, "simulation") do
      {:error, {:public_simulation_selector_forbidden, :self_hosted_inference_core}}
    else
      :ok
    end
  end

  defp reject_public_simulation_selector(_values), do: :ok

  defp public_simulation_entry?({key, _value}), do: key in [:simulation, "simulation"]
  defp public_simulation_entry?(_entry), do: false
end
