defmodule SelfHostedInferenceCore.RuntimeContractTest do
  use ExUnit.Case, async: false

  alias SelfHostedInferenceCore.{
    Backend,
    BackendManifest,
    InstanceSpec
  }

  alias SelfHostedInferenceCore.Backend.StartupPlan
  alias SelfHostedInferenceCore.TestSupport.SpawnedBackend

  setup do
    _ = SelfHostedInferenceCore.unregister_backend(:test_spawned_backend)
    _ = SelfHostedInferenceCore.unregister_backend(:test_invalid_spawned_backend)
    _ = SelfHostedInferenceCore.unregister_backend(:test_invalid_attached_backend)
    _ = SelfHostedInferenceCore.unregister_backend(:test_unsupported_surface_backend)

    :ok = SelfHostedInferenceCore.register_backend(SpawnedBackend)
    :ok = SelfHostedInferenceCore.register_backend(TestInvalidSpawnedBackend)
    :ok = SelfHostedInferenceCore.register_backend(TestInvalidAttachedBackend)
    :ok = SelfHostedInferenceCore.register_backend(TestUnsupportedSurfaceBackend)

    on_exit(fn ->
      _ = SelfHostedInferenceCore.stop_all_instances()
      _ = SelfHostedInferenceCore.unregister_backend(:test_spawned_backend)
      _ = SelfHostedInferenceCore.unregister_backend(:test_invalid_spawned_backend)
      _ = SelfHostedInferenceCore.unregister_backend(:test_invalid_attached_backend)
      _ = SelfHostedInferenceCore.unregister_backend(:test_unsupported_surface_backend)
    end)

    :ok
  end

  test "ensure_instance rejects startup kind drift between the spec and startup plan" do
    spec =
      InstanceSpec.new!(
        backend: :test_spawned_backend,
        startup_kind: :attach_existing_service,
        backend_options: %{model_identity: "runtime-contract-model"}
      )

    assert {:error,
            {:invalid_startup_plan,
             {:requested_startup_kind_mismatch, :attach_existing_service, :spawned}}} =
             SelfHostedInferenceCore.ensure_instance(spec)
  end

  test "ensure_instance rejects spawned plans that do not own a transport" do
    spec = InstanceSpec.new!(backend: :test_invalid_spawned_backend, backend_options: %{})

    assert {:error,
            {:invalid_startup_plan, {:spawned_requires_transport, :test_invalid_spawned_backend}}} =
             SelfHostedInferenceCore.ensure_instance(spec)
  end

  test "ensure_instance rejects attached plans that claim jido managed lifecycle" do
    spec = InstanceSpec.new!(backend: :test_invalid_attached_backend, backend_options: %{})

    assert {:error,
            {:invalid_startup_plan,
             {:management_mode_mismatch, :attach_existing_service, :jido_managed}}} =
             SelfHostedInferenceCore.ensure_instance(spec)
  end

  test "ensure_instance rejects execution surfaces outside the backend manifest" do
    spec =
      InstanceSpec.new!(
        backend: :test_unsupported_surface_backend,
        startup_kind: :attach_existing_service,
        execution_surface: [surface_kind: :ssh_exec],
        backend_options: %{}
      )

    assert {:error,
            {:invalid_startup_plan,
             {:unsupported_execution_surface, :test_unsupported_surface_backend, :ssh_exec,
              [:local_subprocess]}}} =
             SelfHostedInferenceCore.ensure_instance(spec)
  end
end

defmodule TestInvalidSpawnedBackend do
  @moduledoc false

  alias SelfHostedInferenceCore.{Backend, BackendManifest, InstanceSpec}
  alias SelfHostedInferenceCore.Backend.StartupPlan

  @behaviour SelfHostedInferenceCore.Backend

  @impl Backend
  def backend_id, do: :test_invalid_spawned_backend

  @impl Backend
  def manifest do
    BackendManifest.new!(
      backend: backend_id(),
      runtime_kind: :service,
      management_modes: [:jido_managed],
      startup_kind: :spawned,
      protocols: [:openai_chat_completions],
      capabilities: %{streaming?: true},
      supported_surfaces: [:local_subprocess],
      resource_profile: %{profile: :invalid_fixture},
      metadata: %{fixture: :invalid_spawned}
    )
  end

  @impl Backend
  def startup_plan(%InstanceSpec{} = _spec) do
    {:ok,
     %StartupPlan{
       backend: backend_id(),
       instance_key: "test_invalid_spawned_backend",
       startup_kind: :spawned,
       management_mode: :jido_managed,
       transport: nil,
       endpoint_template: %{base_url: "http://127.0.0.1:65535/v1"},
       backend_state: %{}
     }}
  end

  @impl Backend
  def probe_readiness(state), do: {:ready, %{base_url: "http://127.0.0.1:65535/v1"}, state}

  @impl Backend
  def health_check(state), do: {:ok, :healthy, %{}, state}
end

defmodule TestInvalidAttachedBackend do
  @moduledoc false

  alias SelfHostedInferenceCore.{Backend, BackendManifest, InstanceSpec}
  alias SelfHostedInferenceCore.Backend.StartupPlan

  @behaviour SelfHostedInferenceCore.Backend

  @impl Backend
  def backend_id, do: :test_invalid_attached_backend

  @impl Backend
  def manifest do
    BackendManifest.new!(
      backend: backend_id(),
      runtime_kind: :service,
      management_modes: [:externally_managed],
      startup_kind: :attach_existing_service,
      protocols: [:openai_chat_completions],
      capabilities: %{streaming?: true},
      supported_surfaces: [:local_subprocess],
      resource_profile: %{profile: :invalid_fixture},
      metadata: %{fixture: :invalid_attached}
    )
  end

  @impl Backend
  def startup_plan(%InstanceSpec{} = _spec) do
    {:ok,
     %StartupPlan{
       backend: backend_id(),
       instance_key: "test_invalid_attached_backend",
       startup_kind: :attach_existing_service,
       management_mode: :jido_managed,
       transport: nil,
       endpoint_template: %{base_url: "http://127.0.0.1:65535/v1"},
       backend_state: %{}
     }}
  end

  @impl Backend
  def probe_readiness(state), do: {:ready, %{base_url: "http://127.0.0.1:65535/v1"}, state}

  @impl Backend
  def health_check(state), do: {:ok, :healthy, %{}, state}
end

defmodule TestUnsupportedSurfaceBackend do
  @moduledoc false

  alias SelfHostedInferenceCore.{Backend, BackendManifest, InstanceSpec}
  alias SelfHostedInferenceCore.Backend.StartupPlan

  @behaviour SelfHostedInferenceCore.Backend

  @impl Backend
  def backend_id, do: :test_unsupported_surface_backend

  @impl Backend
  def manifest do
    BackendManifest.new!(
      backend: backend_id(),
      runtime_kind: :service,
      management_modes: [:externally_managed],
      startup_kind: :attach_existing_service,
      protocols: [:openai_chat_completions],
      capabilities: %{streaming?: true},
      supported_surfaces: [:local_subprocess],
      resource_profile: %{profile: :unsupported_surface_fixture},
      metadata: %{fixture: :unsupported_surface}
    )
  end

  @impl Backend
  def startup_plan(%InstanceSpec{} = spec) do
    {:ok,
     %StartupPlan{
       backend: backend_id(),
       instance_key: "test_unsupported_surface_backend",
       startup_kind: :attach_existing_service,
       management_mode: :externally_managed,
       transport: nil,
       endpoint_template: %{base_url: "http://127.0.0.1:65535/v1"},
       backend_state: %{execution_surface: spec.execution_surface}
     }}
  end

  @impl Backend
  def probe_readiness(state), do: {:ready, %{base_url: "http://127.0.0.1:65535/v1"}, state}

  @impl Backend
  def health_check(state), do: {:ok, :healthy, %{}, state}
end
