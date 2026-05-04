defmodule SelfHostedInferenceCore.GovernedAuthorityTest do
  use ExUnit.Case, async: false

  alias SelfHostedInferenceCore.{
    ConsumerManifest,
    GovernedAuthority,
    Ollama
  }

  alias SelfHostedInferenceCore.Ollama.AttachSpec
  alias SelfHostedInferenceCore.TestSupport.OllamaService

  setup do
    original_ollama_host = System.get_env("OLLAMA_HOST")

    _ = SelfHostedInferenceCore.stop_all_instances()
    _ = Ollama.unregister_backend()
    :ok = Ollama.register_backend()

    on_exit(fn ->
      _ = SelfHostedInferenceCore.stop_all_instances()
      _ = Ollama.unregister_backend()
      restore_env("OLLAMA_HOST", original_ollama_host)
    end)

    :ok
  end

  test "governed attach spec uses authority materialization instead of OLLAMA_HOST" do
    System.put_env("OLLAMA_HOST", "http://env-ollama.example:11434")

    assert {:ok, spec} = AttachSpec.new(governed_authority: authority())

    assert spec.root_url == "http://governed-ollama.example:11434"
    assert spec.model_identity == "governed-llama"
    assert spec.api_key == "governed-ollama-token"
    assert spec.headers == %{"authorization" => "Bearer governed-ollama-token"}
    refute inspect(spec) =~ "env-ollama"

    assert spec.execution_surface[:surface_kind] == :local_subprocess
    assert spec.execution_surface[:target_id] == "target://self-hosted/ollama"
    assert spec.execution_surface[:surface_ref] == "endpoint://self-hosted/ollama"
    assert spec.execution_surface[:lease_ref] == "attach-grant://self-hosted/ollama"

    assert spec.metadata[:governed_authority_refs] == %{
             attach_grant_ref: "attach-grant://self-hosted/ollama",
             credential_lease_ref: "credential-lease://self-hosted/ollama",
             credential_ref: "credential://self-hosted/ollama",
             endpoint_ref: "endpoint://self-hosted/ollama",
             operation_policy_ref: "operation-policy://self-hosted/ollama/read",
             redaction_ref: "redaction://self-hosted/ollama",
             service_identity_ref: "service-identity://ollama/local",
             target_posture_ref: "target-posture://self-hosted/ollama/no-egress",
             target_ref: "target://self-hosted/ollama"
           }

    refute AttachSpec.instance_key(spec) =~ "governed-ollama-token"
    refute inspect(spec.metadata) =~ "governed-ollama-token"
  end

  test "governed attach spec rejects unmanaged endpoint auth service config and attach fields" do
    rejected_fields = [
      root_url: "http://direct-ollama.example:11434",
      base_url: "http://direct-ollama.example:11434/v1",
      model_identity: "direct-model",
      model: "direct-model",
      api_key: "direct-token",
      headers: %{"authorization" => "Bearer direct-token"},
      execution_surface: [surface_kind: :local_subprocess, target_id: "direct-target"],
      metadata: %{token: "direct-token"},
      ollama_http: fn _method, _path, _payload, _opts -> {:error, :direct_client} end
    ]

    Enum.each(rejected_fields, fn {field, value} ->
      attrs =
        [governed_authority: authority()]
        |> Keyword.put(field, value)

      assert {:error, {:unmanaged_governed_attach_field, ^field}} = AttachSpec.new(attrs)
    end)
  end

  test "ensure_endpoint materializes governed target preference and rejects direct fields" do
    service =
      OllamaService.start!(
        installed_models: ["governed-llama"],
        running_models: ["governed-llama"]
      )

    on_exit(fn ->
      OllamaService.stop(service)
    end)

    governed =
      authority(
        root_url: service.root_url,
        ollama_http: OllamaService.http_stub(service)
      )

    request = %{
      request_id: "req-governed-self-hosted",
      target_preference: %{governed_authority: governed}
    }

    assert {:ok, endpoint, compatibility} =
             SelfHostedInferenceCore.ensure_endpoint(
               request,
               req_llm_consumer(),
               %{run_id: "run-governed-self-hosted"},
               owner_ref: "governed-owner",
               ttl_ms: 5_000,
               await_timeout_ms: 2_000
             )

    assert endpoint.base_url == service.root_url <> "/v1"
    assert endpoint.headers == %{"authorization" => "Bearer governed-ollama-token"}
    assert endpoint.boundary_ref == "endpoint://self-hosted/ollama"
    assert endpoint.metadata.governed_authority_refs.target_ref == "target://self-hosted/ollama"
    assert compatibility.compatible?
    refute inspect(endpoint.metadata) =~ "governed-ollama-token"

    rejected_fields = [
      backend: :ollama,
      startup_kind: :attach_existing_service,
      execution_surface: [surface_kind: :local_subprocess],
      backend_options: %{root_url: service.root_url},
      boot_spec: %{command: "ollama"},
      attach_spec: %{root_url: service.root_url},
      metadata: %{token: "direct-token"},
      root_url: service.root_url,
      api_key: "direct-token",
      headers: %{"authorization" => "Bearer direct-token"}
    ]

    Enum.each(rejected_fields, fn {field, value} ->
      request = %{
        request_id: "req-governed-self-hosted-reject-#{field}",
        target_preference:
          %{governed_authority: governed}
          |> Map.put(field, value)
      }

      assert {:error, {:unmanaged_governed_target_preference_field, ^field}} =
               SelfHostedInferenceCore.ensure_endpoint(
                 request,
                 req_llm_consumer(),
                 %{run_id: "run-governed-self-hosted-reject"},
                 await_timeout_ms: 100
               )
    end)
  end

  test "governed lease and runtime metadata do not contain materialized secrets" do
    service =
      OllamaService.start!(
        installed_models: ["governed-llama"],
        running_models: ["governed-llama"]
      )

    on_exit(fn ->
      OllamaService.stop(service)
    end)

    assert {:ok, resolution} =
             Ollama.resolve_endpoint(
               %{
                 governed_authority:
                   authority(
                     root_url: service.root_url,
                     ollama_http: OllamaService.http_stub(service)
                   )
               },
               req_llm_consumer(),
               owner_ref: "governed-lease-owner",
               ttl_ms: 5_000,
               await_timeout_ms: 2_000
             )

    refute inspect(resolution.lease.metadata) =~ "governed-ollama-token"
    refute inspect(resolution.instance.metadata) =~ "governed-ollama-token"
    refute resolution.instance.instance_id =~ "governed-ollama-token"
  end

  defp authority(overrides \\ []) do
    defaults = [
      backend: :ollama,
      startup_kind: :attach_existing_service,
      endpoint_ref: "endpoint://self-hosted/ollama",
      service_identity_ref: "service-identity://ollama/local",
      target_ref: "target://self-hosted/ollama",
      target_posture_ref: "target-posture://self-hosted/ollama/no-egress",
      attach_grant_ref: "attach-grant://self-hosted/ollama",
      credential_ref: "credential://self-hosted/ollama",
      credential_lease_ref: "credential-lease://self-hosted/ollama",
      operation_policy_ref: "operation-policy://self-hosted/ollama/read",
      redaction_ref: "redaction://self-hosted/ollama",
      root_url: "http://governed-ollama.example:11434",
      model_identity: "governed-llama",
      api_key: "governed-ollama-token",
      headers: %{},
      metadata: %{mode: :governed}
    ]

    defaults
    |> Keyword.merge(overrides)
    |> GovernedAuthority.new!()
  end

  defp req_llm_consumer do
    ConsumerManifest.new!(
      consumer: :jido_integration_req_llm,
      accepted_runtime_kinds: [:service],
      accepted_management_modes: [:externally_managed],
      accepted_protocols: [:openai_chat_completions],
      required_capabilities: %{streaming?: true},
      optional_capabilities: %{tool_calling?: :unknown},
      constraints: %{startup_kind: :attach_existing_service},
      metadata: %{adapter: :req_llm}
    )
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
