defmodule SelfHostedInferenceCore.Phase6ContractsTest do
  use ExUnit.Case, async: false

  alias SelfHostedInferenceCore.AdapterSelectionPolicy
  alias SelfHostedInferenceCore.ConsumerManifest
  alias SelfHostedInferenceCore.LowerSimulationScenario
  alias SelfHostedInferenceCore.Simulation

  setup do
    original_config = Application.get_env(:self_hosted_inference_core, :simulation_backend)

    on_exit(fn ->
      restore_config(original_config)
    end)

    Application.delete_env(:self_hosted_inference_core, :simulation_backend)
    :ok
  end

  test "simulation backend declares the self-hosted lower scenario contract" do
    scenario =
      Simulation.lower_simulation_scenario!(
        "lower-scenario://self-hosted-inference/backend/ready"
      )

    dump = LowerSimulationScenario.dump(scenario)

    assert scenario.contract_version == "ExecutionPlane.LowerSimulationScenario.v1"
    assert scenario.scenario_id == "lower-scenario://self-hosted-inference/backend/ready"
    assert scenario.owner_repo == "self_hosted_inference_core"
    assert scenario.protocol_surface == "self_hosted"
    assert scenario.matcher_class == "deterministic_over_input"
    assert scenario.no_egress_assertion["external_egress"] == "deny"
    assert scenario.no_egress_assertion["process_spawn"] == "deny"

    assert scenario.bounded_evidence_projection["contract_version"] ==
             "ExecutionPlane.LowerSimulationEvidence.v1"

    assert scenario.bounded_evidence_projection["raw_payload_persistence"] == "shape_only"
    assert_json_safe(dump)
    assert LowerSimulationScenario.new!(dump) == scenario
  end

  test "self-hosted lower scenarios reject bad owner, unsupported enums, egress, and raw evidence" do
    assert_raise ArgumentError, ~r/owner_repo.*self_hosted_inference_core/, fn ->
      LowerSimulationScenario.new!(scenario_attrs(%{owner_repo: "execution_plane"}))
    end

    assert_raise ArgumentError, ~r/protocol_surface.*unsupported/, fn ->
      LowerSimulationScenario.new!(scenario_attrs(%{protocol_surface: "process"}))
    end

    assert_raise ArgumentError, ~r/matcher_class.*unsupported/, fn ->
      LowerSimulationScenario.new!(scenario_attrs(%{matcher_class: "semantic_provider"}))
    end

    assert_raise ArgumentError, ~r/semantic provider policy/i, fn ->
      LowerSimulationScenario.new!(Map.put(scenario_attrs(), :provider_refs, ["ollama"]))
    end

    assert_raise ArgumentError, ~r/no_egress_assertion.*external_egress.*deny/, fn ->
      LowerSimulationScenario.new!(
        scenario_attrs(%{no_egress_assertion: %{"external_egress" => "allow"}})
      )
    end

    assert_raise ArgumentError, ~r/raw_payload_persistence.*shape_only/, fn ->
      LowerSimulationScenario.new!(
        scenario_attrs(%{
          bounded_evidence_projection: %{
            "contract_version" => "ExecutionPlane.LowerSimulationEvidence.v1",
            "raw_payload_persistence" => "raw_model_response"
          }
        })
      )
    end

    assert_raise ArgumentError, ~r/ExecutionOutcome.v1.raw_payload.*must not be narrowed/, fn ->
      LowerSimulationScenario.new!(
        scenario_attrs(%{
          bounded_evidence_projection: %{
            "contract_version" => "ExecutionPlane.LowerSimulationEvidence.v1",
            "target_contract" => "ExecutionOutcome.v1.raw_payload",
            "raw_payload_persistence" => "shape_only"
          }
        })
      )
    end
  end

  test "simulation backend declares backend-manifest adapter selection only" do
    policy = Simulation.adapter_selection_policy()
    dump = AdapterSelectionPolicy.dump(policy)

    assert policy.contract_version == "ExecutionPlane.AdapterSelectionPolicy.v1"
    assert policy.owner_repo == "self_hosted_inference_core"
    assert policy.selection_surface == "backend_manifest"
    assert policy.config_key == "self_hosted_inference_core.simulation_backend"
    assert policy.default_value_when_unset == "real_backend_registry"
    assert policy.fail_closed_action_when_misconfigured == "reject_required_or_invalid_manifest"
    assert_json_safe(dump)
    assert AdapterSelectionPolicy.new!(dump) == policy

    assert_raise ArgumentError, ~r/public simulation selector/i, fn ->
      AdapterSelectionPolicy.new!(Map.put(adapter_policy_attrs(), :simulation, "service_mode"))
    end

    assert_raise ArgumentError, ~r/config_key.*public simulation selector/i, fn ->
      AdapterSelectionPolicy.new!(adapter_policy_attrs(%{config_key: "request.simulation"}))
    end
  end

  test "public simulation attrs are rejected before backend selection" do
    assert {:error, {:public_simulation_selector_forbidden, :self_hosted_inference_core}} =
             Simulation.resolve_endpoint(
               %{simulation: :service_mode},
               req_llm_consumer(),
               await_timeout_ms: 100
             )
  end

  test "simulation backend config rejects public selectors before manifest lookup" do
    Application.put_env(:self_hosted_inference_core, :simulation_backend,
      simulation: :service_mode
    )

    assert {:error, {:public_simulation_selector_forbidden, :self_hosted_inference_core}} =
             Simulation.active_manifest()
  end

  defp scenario_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        scenario_id: "lower-scenario://self-hosted-inference/backend/ready",
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
      },
      overrides
    )
  end

  defp adapter_policy_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        selection_surface: "backend_manifest",
        owner_repo: "self_hosted_inference_core",
        config_key: "self_hosted_inference_core.simulation_backend",
        default_value_when_unset: "real_backend_registry",
        fail_closed_action_when_misconfigured: "reject_required_or_invalid_manifest"
      },
      overrides
    )
  end

  defp req_llm_consumer do
    ConsumerManifest.new!(
      consumer: :jido_integration_req_llm,
      accepted_runtime_kinds: [:service],
      accepted_management_modes: [:jido_managed],
      accepted_protocols: [:openai_chat_completions],
      required_capabilities: %{streaming?: true},
      optional_capabilities: %{deterministic_response?: true},
      constraints: %{startup_kind: :spawned},
      metadata: %{adapter: :req_llm}
    )
  end

  defp restore_config(nil),
    do: Application.delete_env(:self_hosted_inference_core, :simulation_backend)

  defp restore_config(config) do
    Application.put_env(:self_hosted_inference_core, :simulation_backend, config)
  end

  defp assert_json_safe(value) when is_binary(value) or is_boolean(value) or is_nil(value),
    do: :ok

  defp assert_json_safe(value) when is_integer(value) or is_float(value), do: :ok

  defp assert_json_safe(value) when is_list(value), do: Enum.each(value, &assert_json_safe/1)

  defp assert_json_safe(value) when is_map(value) do
    assert Enum.all?(Map.keys(value), &is_binary/1)
    Enum.each(value, fn {_key, nested} -> assert_json_safe(nested) end)
  end
end
