defmodule SelfHostedInferenceCore.SimulationBackendTest do
  use ExUnit.Case, async: false

  alias SelfHostedInferenceCore.{
    CompatibilityResult,
    ConsumerManifest,
    EndpointDescriptor,
    Simulation
  }

  setup do
    original_config = Application.get_env(:self_hosted_inference_core, :simulation_backend)

    _ = SelfHostedInferenceCore.stop_all_instances()
    _ = Simulation.unregister_backend()
    :ok = Simulation.register_backend()

    on_exit(fn ->
      _ = SelfHostedInferenceCore.stop_all_instances()
      _ = Simulation.unregister_backend()
      restore_config(original_config)
    end)

    :ok
  end

  test "publishes a configured simulated endpoint without spawning a real backend" do
    put_simulation_manifest(
      deterministic_response: %{
        response_ref: "response://phase5prelim/self-hosted/ok",
        body: %{"choices" => [%{"message" => %{"content" => "simulated self-hosted ok"}}]},
        usage: %{"input_tokens" => 11, "output_tokens" => 4}
      }
    )

    assert %CompatibilityResult{compatible?: true, reason: :protocol_match} =
             Simulation.compatibility(req_llm_consumer())

    assert {:ok, resolution} =
             Simulation.resolve_endpoint(
               %{backend_options: %{model_identity: "phase5prelim-model"}},
               req_llm_consumer(),
               owner_ref: "phase5prelim-owner",
               ttl_ms: 5_000,
               await_timeout_ms: 1_000
             )

    assert %EndpointDescriptor{
             management_mode: :jido_managed,
             target_class: :self_hosted_endpoint,
             protocol: :openai_chat_completions,
             base_url:
               "http://127.0.0.1:65535/self-hosted-simulation/phase5prelim-self-hosted/v1",
             provider_identity: :self_hosted_simulation,
             model_identity: "phase5prelim-model",
             source_runtime: :self_hosted_simulation,
             source_runtime_ref: "phase5prelim-self-hosted",
             lease_ref: lease_ref,
             health_ref: "self-hosted-simulation://health/phase5prelim-self-hosted",
             boundary_ref: "phase5prelim-self-hosted"
           } = resolution.endpoint

    assert is_binary(lease_ref)
    refute resolution.reused?
    assert resolution.compatibility.compatible?
    assert resolution.lease.lease_ref == lease_ref
    assert resolution.instance.metadata.side_effect_policy == :deny_process_spawn
    assert resolution.endpoint.metadata.simulation_manifest_ref == "phase5prelim-self-hosted"
    assert resolution.endpoint.metadata.scenario_ref == "lower-simulation://self-hosted/ready"

    assert resolution.endpoint.metadata.deterministic_response_ref ==
             "response://phase5prelim/self-hosted/ok"

    assert resolution.endpoint.metadata.deterministic_response.body["choices"] != []

    assert {:ok, published} =
             SelfHostedInferenceCore.publish_endpoint(resolution.instance.instance_id)

    assert published.base_url == resolution.endpoint.base_url
  end

  test "health checks reflect the configured simulation manifest status" do
    put_simulation_manifest(health_status: :degraded)

    assert {:ok, resolution} =
             Simulation.resolve_endpoint(
               %{},
               req_llm_consumer(),
               owner_ref: "phase5prelim-health",
               ttl_ms: 5_000,
               await_timeout_ms: 1_000
             )

    assert {:ok, snapshot} =
             wait_until(fn ->
               case SelfHostedInferenceCore.lookup_instance(resolution.instance.instance_id) do
                 {:ok, %{health_status: :degraded} = snapshot} -> {:ok, snapshot}
                 _other -> :retry
               end
             end)

    assert snapshot.health_status == :degraded
  end

  test "missing configured manifest fails before lower transport startup" do
    Application.delete_env(:self_hosted_inference_core, :simulation_backend)

    assert {:error, {:simulation_backend_not_configured, :simulation_backend}} =
             Simulation.resolve_endpoint(%{}, req_llm_consumer(), await_timeout_ms: 100)
  end

  test "invalid configured manifest fails before lower transport startup" do
    Application.put_env(:self_hosted_inference_core, :simulation_backend,
      active_manifest_ref: "phase5prelim-invalid",
      manifests: %{
        "phase5prelim-invalid" => %{
          scenario_ref: "lower-simulation://self-hosted/invalid"
        }
      }
    )

    assert {:error, {:invalid_deterministic_response, nil}} =
             Simulation.resolve_endpoint(%{}, req_llm_consumer(), await_timeout_ms: 100)
  end

  test "boot specs and non-simulation execution surfaces are rejected as bypass attempts" do
    put_simulation_manifest()

    assert {:error, {:simulation_backend_bypass_denied, :boot_spec}} =
             Simulation.resolve_endpoint(
               %{backend_options: %{boot_spec: %{command: "llama-server"}}},
               req_llm_consumer(),
               await_timeout_ms: 100
             )

    assert {:error, {:simulation_backend_bypass_denied, {:execution_surface, :local_subprocess}}} =
             Simulation.resolve_endpoint(
               %{execution_surface: [surface_kind: :local_subprocess]},
               req_llm_consumer(),
               await_timeout_ms: 100
             )
  end

  defp put_simulation_manifest(overrides \\ []) do
    manifest =
      %{
        manifest_ref: "phase5prelim-self-hosted",
        scenario_ref: "lower-simulation://self-hosted/ready",
        base_url: "http://127.0.0.1:65535/self-hosted-simulation/phase5prelim-self-hosted/v1",
        model_identity: "phase5prelim-model",
        deterministic_response: %{
          response_ref: "response://phase5prelim/self-hosted/default",
          body: %{"choices" => [%{"message" => %{"content" => "default simulated response"}}]},
          usage: %{"input_tokens" => 1, "output_tokens" => 3}
        }
      }
      |> Map.merge(Map.new(overrides))

    Application.put_env(:self_hosted_inference_core, :simulation_backend,
      active_manifest_ref: "phase5prelim-self-hosted",
      manifests: %{"phase5prelim-self-hosted" => manifest}
    )
  end

  defp req_llm_consumer(overrides \\ []) do
    [
      consumer: :jido_integration_req_llm,
      accepted_runtime_kinds: [:service],
      accepted_management_modes: [:jido_managed],
      accepted_protocols: [:openai_chat_completions],
      required_capabilities: %{streaming?: true},
      optional_capabilities: %{deterministic_response?: true},
      constraints: %{startup_kind: :spawned},
      metadata: %{adapter: :req_llm}
    ]
    |> Keyword.merge(overrides)
    |> ConsumerManifest.new!()
  end

  defp restore_config(nil) do
    Application.delete_env(:self_hosted_inference_core, :simulation_backend)
  end

  defp restore_config(config) do
    Application.put_env(:self_hosted_inference_core, :simulation_backend, config)
  end

  defp wait_until(fun, attempts \\ 80)

  defp wait_until(_fun, 0), do: {:error, :timeout}

  defp wait_until(fun, attempts) when is_function(fun, 0) do
    case fun.() do
      {:ok, value} ->
        {:ok, value}

      :retry ->
        Process.sleep(25)
        wait_until(fun, attempts - 1)
    end
  end
end
