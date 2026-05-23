defmodule SelfHostedInferenceCore.AdapterRefRegistryTest do
  use ExUnit.Case, async: false

  alias SelfHostedInferenceCore.{
    AdapterRef,
    InstanceSpec,
    RouteLogits,
    RuntimeRegistry
  }

  alias SelfHostedInferenceCore.TestSupport.SpawnedBackend

  setup do
    _ = SelfHostedInferenceCore.unregister_backend(:test_spawned_backend)
    :ok = SelfHostedInferenceCore.register_backend(SpawnedBackend)

    on_exit(fn ->
      _ = SelfHostedInferenceCore.stop_all_instances()
      _ = SelfHostedInferenceCore.unregister_backend(:test_spawned_backend)
    end)

    :ok
  end

  test "instance specs without adapter_ref remain backward compatible" do
    spec =
      InstanceSpec.new!(
        backend: :test_spawned_backend,
        backend_options: %{model_identity: "legacy"}
      )

    assert spec.adapter_ref == nil
    assert InstanceSpec.backend_id(spec) == :test_spawned_backend
    assert InstanceSpec.adapter_ref(spec) == nil
    assert InstanceSpec.registry_key(spec) == {:test_spawned_backend, nil}
  end

  test "instance specs with adapter_ref produce stable registry keys" do
    adapter_ref =
      AdapterRef.new!(
        id: :trinity_qwen3_0_6b_sakana,
        version: "0.1.0",
        contract: :route_logits_v1
      )

    spec =
      InstanceSpec.new!(
        backend: :test_spawned_backend,
        adapter_ref: adapter_ref,
        backend_options: %{model_identity: "adapter-a"}
      )

    assert InstanceSpec.adapter_ref(spec) == adapter_ref

    assert InstanceSpec.registry_key(spec) ==
             {:test_spawned_backend, {:trinity_qwen3_0_6b_sakana, "0.1.0", :route_logits_v1}}
  end

  test "registry can find an instance by instance id and by backend adapter ref" do
    adapter_ref = adapter_ref(:adapter_a)
    spec = spec("adapter-a", adapter_ref)

    assert {:ok, %{instance: snapshot, reused?: false}} =
             SelfHostedInferenceCore.ensure_instance(spec)

    pid_by_id = RuntimeRegistry.whereis(snapshot.instance_id)
    pid_by_adapter = RuntimeRegistry.whereis({:test_spawned_backend, adapter_ref})

    assert is_pid(pid_by_id)
    assert pid_by_adapter == pid_by_id
    assert snapshot.adapter_ref == adapter_ref
    assert snapshot.metadata.adapter_ref == adapter_ref
  end

  test "duplicate backend adapter refs reuse the existing runtime instance" do
    adapter_ref = adapter_ref(:adapter_reused)

    assert {:ok, %{instance: first, reused?: false}} =
             SelfHostedInferenceCore.ensure_instance(spec("first-model", adapter_ref))

    assert {:ok, %{instance: second, reused?: true}} =
             SelfHostedInferenceCore.ensure_instance(spec("second-model", adapter_ref))

    assert second.instance_id == first.instance_id

    assert RuntimeRegistry.whereis({:test_spawned_backend, adapter_ref}) ==
             RuntimeRegistry.whereis(first.instance_id)
  end

  test "same backend with distinct adapter refs creates distinct registry entries" do
    adapter_a = adapter_ref(:adapter_distinct_a)
    adapter_b = adapter_ref(:adapter_distinct_b)

    assert {:ok, %{instance: first, reused?: false}} =
             SelfHostedInferenceCore.ensure_instance(spec("distinct-a", adapter_a))

    assert {:ok, %{instance: second, reused?: false}} =
             SelfHostedInferenceCore.ensure_instance(spec("distinct-b", adapter_b))

    refute first.instance_id == second.instance_id
    assert RuntimeRegistry.whereis({:test_spawned_backend, adapter_a}) != nil
    assert RuntimeRegistry.whereis({:test_spawned_backend, adapter_b}) != nil
  end

  test "runtime registry lists instances by backend and by adapter" do
    adapter_ref = adapter_ref(:adapter_listed)

    assert {:ok, %{instance: snapshot, reused?: false}} =
             SelfHostedInferenceCore.ensure_instance(spec("listed", adapter_ref))

    assert Enum.map(RuntimeRegistry.list_by_backend(:test_spawned_backend), & &1.instance_id) == [
             snapshot.instance_id
           ]

    assert Enum.map(
             RuntimeRegistry.list_by_adapter(:test_spawned_backend, adapter_ref),
             & &1.instance_id
           ) ==
             [snapshot.instance_id]
  end

  test "route logits struct carries the generic adapter route-head result contract" do
    logits = %RouteLogits{
      role_logits: [0.1, 0.9],
      agent_logits: [0.7, 0.3],
      selected_role_id: "implementer",
      selected_agent_id: "agent-1",
      token_count: 42,
      transcript_hash: "transcript",
      route_hash_inputs: %{role: "implementer"},
      backend_label: "EXLA.Backend<cuda:0>",
      runtime_profile: :cuda_exla,
      margins: %{role: 0.8}
    }

    assert logits.selected_role_id == "implementer"
    assert logits.runtime_profile == :cuda_exla
  end

  defp spec(model_identity, adapter_ref) do
    InstanceSpec.new!(
      backend: :test_spawned_backend,
      adapter_ref: adapter_ref,
      backend_options: %{model_identity: model_identity}
    )
  end

  defp adapter_ref(id) do
    AdapterRef.new!(id: id, version: "0.1.0", contract: :route_logits_v1)
  end
end
