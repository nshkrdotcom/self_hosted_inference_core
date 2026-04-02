defmodule SelfHostedInferenceCore.KernelTest do
  use ExUnit.Case, async: false

  alias SelfHostedInferenceCore.{
    BackendManifest,
    CompatibilityResult,
    ConsumerManifest,
    EndpointDescriptor,
    InstanceSpec,
    LeaseRef
  }

  alias SelfHostedInferenceCore.TestSupport.{
    AttachedBackend,
    ExternalService,
    SpawnedBackend
  }

  setup do
    _ = SelfHostedInferenceCore.unregister_backend(:test_spawned_backend)
    _ = SelfHostedInferenceCore.unregister_backend(:test_attached_backend)

    :ok = SelfHostedInferenceCore.register_backend(SpawnedBackend)
    :ok = SelfHostedInferenceCore.register_backend(AttachedBackend)

    on_exit(fn ->
      _ = SelfHostedInferenceCore.stop_all_instances()
      _ = SelfHostedInferenceCore.unregister_backend(:test_spawned_backend)
      _ = SelfHostedInferenceCore.unregister_backend(:test_attached_backend)
    end)

    :ok
  end

  test "backend registry exposes registered manifests" do
    assert {:ok, %BackendManifest{} = manifest} =
             SelfHostedInferenceCore.fetch_backend_manifest(:test_spawned_backend)

    assert manifest.backend == :test_spawned_backend
    assert manifest.runtime_kind == :service
    assert manifest.startup_kind == :spawned
    assert manifest.management_modes == [:jido_managed]

    registered_backends =
      SelfHostedInferenceCore.list_backends()
      |> Enum.map(& &1.backend)
      |> Enum.sort()

    assert registered_backends == [:test_attached_backend, :test_spawned_backend]
  end

  test "compatibility reports protocol matches and startup-kind mismatches" do
    assert %CompatibilityResult{compatible?: true, reason: :protocol_match} =
             SelfHostedInferenceCore.compatibility(
               :test_spawned_backend,
               req_llm_consumer()
             )

    assert %CompatibilityResult{
             compatible?: false,
             reason: :startup_kind_unsupported,
             missing_requirements: [:startup_kind]
           } =
             SelfHostedInferenceCore.compatibility(
               :test_spawned_backend,
               req_llm_consumer(constraints: %{startup_kind: :attach_existing_service})
             )
  end

  test "spawned instances publish endpoints and reuse compatible leases" do
    spec =
      InstanceSpec.new!(
        backend: :test_spawned_backend,
        backend_options: %{model_identity: "demo-spawned-model"}
      )

    assert {:ok, first} =
             SelfHostedInferenceCore.resolve_endpoint(
               spec,
               req_llm_consumer(),
               owner_ref: "owner-a",
               ttl_ms: 5_000
             )

    assert %EndpointDescriptor{
             runtime_kind: :service,
             management_mode: :jido_managed,
             target_class: :self_hosted_endpoint,
             protocol: :openai_chat_completions,
             base_url: base_url
           } = first.endpoint

    assert String.starts_with?(base_url, "http://127.0.0.1:")
    assert %LeaseRef{lease_ref: first_lease_ref} = first.lease
    refute first.reused?

    assert {:ok, second} =
             SelfHostedInferenceCore.resolve_endpoint(
               spec,
               req_llm_consumer(),
               owner_ref: "owner-b",
               ttl_ms: 5_000
             )

    assert second.reused?
    assert second.instance.instance_id == first.instance.instance_id
    assert second.endpoint.base_url == first.endpoint.base_url
    assert second.lease.lease_ref != first_lease_ref

    assert {:ok, published} = SelfHostedInferenceCore.publish_endpoint(first.instance.instance_id)
    assert published.base_url == first.endpoint.base_url
    assert published.management_mode == :jido_managed

    assert :ok =
             SelfHostedInferenceCore.release_lease(first.instance.instance_id, first_lease_ref)

    assert :ok =
             SelfHostedInferenceCore.release_lease(
               second.instance.instance_id,
               second.lease.lease_ref
             )
  end

  test "health monitoring tracks degraded spawned services" do
    spec =
      InstanceSpec.new!(
        backend: :test_spawned_backend,
        backend_options: %{model_identity: "demo-health-model"}
      )

    assert {:ok, resolution} =
             SelfHostedInferenceCore.resolve_endpoint(
               spec,
               req_llm_consumer(),
               owner_ref: "health-owner",
               ttl_ms: 5_000
             )

    assert :ok = ExternalService.set_health(resolution.endpoint.base_url, :degraded)

    assert {:ok, snapshot} =
             wait_until(fn ->
               case SelfHostedInferenceCore.lookup_instance(resolution.instance.instance_id) do
                 {:ok, %{health_status: :degraded} = instance} -> {:ok, instance}
                 _other -> :retry
               end
             end)

    assert snapshot.health_status == :degraded

    assert :ok =
             SelfHostedInferenceCore.release_lease(
               resolution.instance.instance_id,
               resolution.lease.lease_ref
             )
  end

  test "attach_existing_service publishes externally managed endpoints without taking daemon ownership" do
    external_service = ExternalService.start!()

    on_exit(fn ->
      ExternalService.stop(external_service)
    end)

    spec =
      InstanceSpec.new!(
        backend: :test_attached_backend,
        backend_options: %{
          model_identity: "demo-attached-model",
          root_url: external_service.root_url
        }
      )

    consumer =
      req_llm_consumer(accepted_management_modes: [:externally_managed])

    assert {:ok, first} =
             SelfHostedInferenceCore.resolve_endpoint(
               spec,
               consumer,
               owner_ref: "external-owner-a",
               ttl_ms: 5_000
             )

    assert %EndpointDescriptor{
             management_mode: :externally_managed,
             base_url: base_url
           } = first.endpoint

    assert base_url == external_service.root_url <> "/v1"
    refute first.reused?

    assert {:ok, second} =
             SelfHostedInferenceCore.resolve_endpoint(
               spec,
               consumer,
               owner_ref: "external-owner-b",
               ttl_ms: 5_000
             )

    assert second.reused?
    assert second.instance.instance_id == first.instance.instance_id

    assert :ok = SelfHostedInferenceCore.stop_instance(first.instance.instance_id)
    assert ExternalService.alive?(external_service)

    assert :ok =
             SelfHostedInferenceCore.release_lease(
               first.instance.instance_id,
               first.lease.lease_ref
             )

    assert :ok =
             SelfHostedInferenceCore.release_lease(
               second.instance.instance_id,
               second.lease.lease_ref
             )
  end

  defp req_llm_consumer(overrides \\ []) do
    attrs =
      [
        consumer: :jido_integration_req_llm,
        accepted_runtime_kinds: [:service],
        accepted_management_modes: [:jido_managed, :externally_managed],
        accepted_protocols: [:openai_chat_completions],
        required_capabilities: %{streaming?: true},
        optional_capabilities: %{},
        constraints: %{},
        metadata: %{}
      ]
      |> Keyword.merge(overrides)

    ConsumerManifest.new!(attrs)
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
