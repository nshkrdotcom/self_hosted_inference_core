defmodule SelfHostedInferenceCore.OllamaBackendTest do
  use ExUnit.Case, async: false

  alias SelfHostedInferenceCore.{
    CompatibilityResult,
    ConsumerManifest,
    EndpointDescriptor
  }

  alias SelfHostedInferenceCore.Ollama
  alias SelfHostedInferenceCore.TestSupport.OllamaService

  setup do
    _ = SelfHostedInferenceCore.stop_all_instances()
    _ = Ollama.unregister_backend()
    :ok = Ollama.register_backend()

    on_exit(fn ->
      _ = SelfHostedInferenceCore.stop_all_instances()
      _ = Ollama.unregister_backend()
    end)

    :ok
  end

  test "registers an externally managed ollama attach manifest and compatibility result" do
    assert {:ok, manifest} = SelfHostedInferenceCore.fetch_backend_manifest(:ollama)
    assert manifest.backend == :ollama
    assert manifest.runtime_kind == :service
    assert manifest.startup_kind == :attach_existing_service
    assert manifest.management_modes == [:externally_managed]
    assert manifest.protocols == [:openai_chat_completions]

    assert %CompatibilityResult{
             compatible?: true,
             reason: :protocol_match,
             resolved_runtime_kind: :service,
             resolved_management_mode: :externally_managed
           } = Ollama.compatibility(req_llm_consumer())

    assert %CompatibilityResult{
             compatible?: false,
             reason: :management_mode_mismatch,
             missing_requirements: [:management_mode]
           } =
             Ollama.compatibility(req_llm_consumer(accepted_management_modes: [:jido_managed]))
  end

  test "attach readiness waits for the requested model and publishes an externally managed endpoint" do
    service = OllamaService.start!(installed_models: [], running_models: [])

    on_exit(fn ->
      OllamaService.stop(service)
    end)

    Task.start(fn ->
      Process.sleep(100)
      :ok = OllamaService.set_installed_models(service, ["llama3.2"])
    end)

    assert {:ok, resolution} =
             Ollama.resolve_endpoint(
               %{
                 root_url: service.root_url,
                 model_identity: "llama3.2",
                 ollama_http: OllamaService.http_stub(service),
                 ready_timeout_ms: 2_000,
                 readiness_interval_ms: 25,
                 health_interval_ms: 50
               },
               req_llm_consumer(),
               owner_ref: "ollama-owner-a",
               ttl_ms: 5_000,
               await_timeout_ms: 2_000
             )

    assert %EndpointDescriptor{
             management_mode: :externally_managed,
             base_url: base_url,
             provider_identity: :ollama,
             model_identity: "llama3.2",
             source_runtime: :ollama,
             source_runtime_ref: source_runtime_ref
           } = resolution.endpoint

    assert base_url == service.root_url <> "/v1"
    assert source_runtime_ref == service.root_url
    refute resolution.reused?
    assert resolution.compatibility.compatible?
    assert resolution.compatibility.resolved_management_mode == :externally_managed
    assert resolution.lease.lease_ref == resolution.endpoint.lease_ref
  end

  test "health interpretation marks an attached ollama endpoint degraded until the model is running" do
    service =
      OllamaService.start!(
        installed_models: ["llama3.2"],
        running_models: []
      )

    on_exit(fn ->
      OllamaService.stop(service)
    end)

    assert {:ok, resolution} =
             Ollama.resolve_endpoint(
               %{
                 root_url: service.root_url,
                 model_identity: "llama3.2",
                 ollama_http: OllamaService.http_stub(service),
                 ready_timeout_ms: 2_000,
                 readiness_interval_ms: 25,
                 health_interval_ms: 50
               },
               req_llm_consumer(),
               owner_ref: "ollama-owner-b",
               ttl_ms: 5_000,
               await_timeout_ms: 2_000
             )

    assert {:ok, degraded_snapshot} =
             wait_until(fn ->
               case SelfHostedInferenceCore.lookup_instance(resolution.instance.instance_id) do
                 {:ok, %{health_status: :degraded} = snapshot} -> {:ok, snapshot}
                 _other -> :retry
               end
             end)

    assert degraded_snapshot.health_status == :degraded

    assert :ok = OllamaService.set_running_models(service, ["llama3.2"])

    assert {:ok, healthy_snapshot} =
             wait_until(fn ->
               case SelfHostedInferenceCore.lookup_instance(resolution.instance.instance_id) do
                 {:ok, %{health_status: :healthy} = snapshot} -> {:ok, snapshot}
                 _other -> :retry
               end
             end)

    assert healthy_snapshot.health_status == :healthy
  end

  test "ensure_endpoint infers the ollama model identity from request.model_preference" do
    service =
      OllamaService.start!(
        installed_models: ["llama3.2"],
        running_models: ["llama3.2"]
      )

    on_exit(fn ->
      OllamaService.stop(service)
    end)

    request = %{
      request_id: "req-ollama-endpoint-1",
      model_preference: %{provider: "openai", id: "llama3.2"},
      target_preference: %{
        backend: :ollama,
        backend_options: %{
          root_url: service.root_url,
          ollama_http: OllamaService.http_stub(service)
        }
      }
    }

    context = %{
      run_id: "run-ollama-endpoint-1",
      attempt_id: "run-ollama-endpoint-1:1"
    }

    assert {:ok, endpoint, compatibility} =
             SelfHostedInferenceCore.ensure_endpoint(
               request,
               req_llm_consumer(),
               context,
               owner_ref: "ollama-owner-c",
               ttl_ms: 5_000,
               await_timeout_ms: 2_000
             )

    assert endpoint.model_identity == "llama3.2"
    assert endpoint.base_url == service.root_url <> "/v1"
    assert endpoint.management_mode == :externally_managed
    assert compatibility.compatible?
  end

  test "stopping an attached ollama instance does not stop the external daemon" do
    service =
      OllamaService.start!(
        installed_models: ["llama3.2"],
        running_models: ["llama3.2"]
      )

    on_exit(fn ->
      OllamaService.stop(service)
    end)

    assert {:ok, resolution} =
             Ollama.resolve_endpoint(
               %{
                 root_url: service.root_url,
                 model_identity: "llama3.2",
                 ollama_http: OllamaService.http_stub(service),
                 ready_timeout_ms: 2_000,
                 readiness_interval_ms: 25,
                 health_interval_ms: 50
               },
               req_llm_consumer(),
               owner_ref: "ollama-owner-d",
               ttl_ms: 5_000,
               await_timeout_ms: 2_000
             )

    assert :ok = SelfHostedInferenceCore.stop_instance(resolution.instance.instance_id)
    assert OllamaService.alive?(service)
  end

  defp req_llm_consumer(overrides \\ []) do
    [
      consumer: :jido_integration_req_llm,
      accepted_runtime_kinds: [:service],
      accepted_management_modes: [:externally_managed],
      accepted_protocols: [:openai_chat_completions],
      required_capabilities: %{streaming?: true},
      optional_capabilities: %{tool_calling?: :unknown},
      constraints: %{startup_kind: :attach_existing_service},
      metadata: %{adapter: :req_llm}
    ]
    |> Keyword.merge(overrides)
    |> ConsumerManifest.new!()
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
