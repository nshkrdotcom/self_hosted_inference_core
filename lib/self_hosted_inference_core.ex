defmodule SelfHostedInferenceCore do
  @moduledoc """
  Service-runtime kernel for self-hosted inference backends.
  """

  alias SelfHostedInferenceCore.{
    Backend,
    BackendManifest,
    BackendRegistry,
    Compatibility,
    CompatibilityResult,
    ConsumerManifest,
    EndpointDescriptor,
    InstanceSpec,
    LeaseRef,
    RuntimeInstance,
    RuntimeRegistry,
    RuntimeSnapshot
  }

  @type ensure_result :: %{
          instance: RuntimeSnapshot.t(),
          reused?: boolean()
        }

  @type resolve_result :: %{
          instance: RuntimeSnapshot.t(),
          endpoint: EndpointDescriptor.t(),
          lease: LeaseRef.t(),
          compatibility: CompatibilityResult.t(),
          reused?: boolean()
        }

  @type ensure_endpoint_result ::
          {:ok, EndpointDescriptor.t(), CompatibilityResult.t()} | {:error, term()}

  @spec metadata() :: %{app: atom(), version: String.t()}
  def metadata do
    %{
      app: :self_hosted_inference_core,
      version: to_string(Application.spec(:self_hosted_inference_core, :vsn))
    }
  end

  @spec register_backend(module()) :: :ok | {:error, term()}
  def register_backend(module), do: BackendRegistry.register(module)

  @spec unregister_backend(atom()) :: :ok
  def unregister_backend(backend), do: BackendRegistry.unregister(backend)

  @spec fetch_backend_manifest(atom()) :: {:ok, BackendManifest.t()} | {:error, term()}
  def fetch_backend_manifest(backend), do: BackendRegistry.fetch_manifest(backend)

  @spec list_backends() :: [BackendManifest.t()]
  def list_backends, do: BackendRegistry.list_manifests()

  @spec compatibility(atom(), ConsumerManifest.t()) :: CompatibilityResult.t()
  def compatibility(backend, %ConsumerManifest{} = consumer_manifest) do
    case fetch_backend_manifest(backend) do
      {:ok, %BackendManifest{} = backend_manifest} ->
        Compatibility.resolve(backend_manifest, consumer_manifest)

      {:error, reason} ->
        CompatibilityResult.new!(
          compatible?: false,
          reason: :backend_unregistered,
          missing_requirements: [:backend],
          metadata: %{reason: reason}
        )
    end
  end

  @spec ensure_instance(InstanceSpec.t() | keyword() | map(), keyword()) ::
          {:ok, ensure_result()} | {:error, term()}
  def ensure_instance(spec_or_attrs, opts \\ []) do
    with {:ok, %InstanceSpec{} = spec} <- normalize_spec(spec_or_attrs),
         {:ok, backend_module} <- BackendRegistry.fetch_module(spec.backend),
         {:ok, %Backend.StartupPlan{} = plan} <- backend_module.startup_plan(spec),
         :ok <- validate_startup_plan(spec, backend_module, plan),
         {:ok, pid, reused?} <- RuntimeRegistry.ensure_instance(plan, backend_module),
         {:ok, %RuntimeSnapshot{} = snapshot} <-
           RuntimeInstance.await_ready(pid, await_timeout(opts)) do
      {:ok, %{instance: snapshot, reused?: reused?}}
    end
  end

  @spec resolve_endpoint(InstanceSpec.t() | keyword() | map(), ConsumerManifest.t(), keyword()) ::
          {:ok, resolve_result()} | {:error, term()}
  def resolve_endpoint(spec_or_attrs, %ConsumerManifest{} = consumer_manifest, opts \\ []) do
    with {:ok, %InstanceSpec{} = spec} <- normalize_spec(spec_or_attrs),
         %CompatibilityResult{} = compatibility_result <-
           compatibility(spec.backend, consumer_manifest),
         true <-
           compatibility_result.compatible? || {:error, {:incompatible, compatibility_result}},
         {:ok, %{instance: %RuntimeSnapshot{} = snapshot, reused?: reused?}} <-
           ensure_instance(spec, opts),
         {:ok, %{endpoint: %EndpointDescriptor{} = endpoint, lease: %LeaseRef{} = lease}} <-
           lease_instance(snapshot.instance_id, opts) do
      {:ok,
       %{
         instance: snapshot,
         endpoint: endpoint,
         lease: lease,
         compatibility: compatibility_result,
         reused?: reused?
       }}
    end
  end

  @spec ensure_endpoint(map(), ConsumerManifest.t(), map() | keyword(), keyword()) ::
          ensure_endpoint_result()
  def ensure_endpoint(request, consumer_manifest, context, opts \\ [])

  def ensure_endpoint(request, %ConsumerManifest{} = consumer_manifest, context, opts)
      when is_map(request) and (is_map(context) or is_list(context)) do
    with {:ok, %InstanceSpec{} = spec} <- normalize_request_instance_spec(request, context),
         {:ok, %{endpoint: %EndpointDescriptor{} = endpoint, compatibility: compatibility}} <-
           resolve_endpoint(spec, consumer_manifest, opts) do
      {:ok, endpoint, compatibility}
    end
  end

  def ensure_endpoint(request, %ConsumerManifest{} = _consumer_manifest, _context, _opts)
      when not is_map(request) do
    {:error, {:invalid_request, request}}
  end

  def ensure_endpoint(_request, consumer_manifest, _context, _opts) do
    {:error, {:invalid_consumer_manifest, consumer_manifest}}
  end

  @spec lease_instance(String.t(), keyword()) ::
          {:ok, %{endpoint: EndpointDescriptor.t(), lease: LeaseRef.t()}} | {:error, term()}
  def lease_instance(instance_id, opts \\ []) when is_binary(instance_id) do
    case RuntimeRegistry.whereis(instance_id) do
      pid when is_pid(pid) ->
        RuntimeInstance.acquire_lease(pid, opts)

      nil ->
        {:error, :not_found}
    end
  end

  @spec release_lease(String.t(), String.t()) :: :ok
  def release_lease(instance_id, lease_ref)
      when is_binary(instance_id) and is_binary(lease_ref) do
    case RuntimeRegistry.whereis(instance_id) do
      pid when is_pid(pid) -> RuntimeInstance.release_lease(pid, lease_ref)
      nil -> :ok
    end
  end

  @spec publish_endpoint(String.t()) :: {:ok, EndpointDescriptor.t()} | {:error, term()}
  def publish_endpoint(instance_id) when is_binary(instance_id) do
    case RuntimeRegistry.whereis(instance_id) do
      pid when is_pid(pid) -> RuntimeInstance.publish_endpoint(pid)
      nil -> {:error, :not_found}
    end
  end

  @spec lookup_instance(String.t()) :: {:ok, RuntimeSnapshot.t()} | {:error, :not_found}
  def lookup_instance(instance_id) when is_binary(instance_id) do
    case RuntimeRegistry.whereis(instance_id) do
      pid when is_pid(pid) -> {:ok, RuntimeInstance.snapshot(pid)}
      nil -> {:error, :not_found}
    end
  end

  @spec list_instances() :: [RuntimeSnapshot.t()]
  def list_instances, do: RuntimeRegistry.list_instances()

  @spec stop_instance(String.t()) :: :ok
  def stop_instance(instance_id) when is_binary(instance_id),
    do: RuntimeRegistry.stop_instance(instance_id)

  @spec stop_all_instances() :: :ok
  def stop_all_instances, do: RuntimeRegistry.stop_all_instances()

  defp normalize_spec(%InstanceSpec{} = spec), do: {:ok, spec}
  defp normalize_spec(attrs) when is_list(attrs) or is_map(attrs), do: InstanceSpec.new(attrs)

  defp normalize_request_instance_spec(request, context) do
    with {:ok, target_preference} <- fetch_target_preference(request),
         {:ok, backend} <- fetch_target_preference_field(target_preference, :backend) do
      metadata =
        target_preference
        |> optional_target_preference_map(:metadata, %{})
        |> Map.merge(context_metadata(request, context))

      backend_options =
        target_preference
        |> optional_target_preference_map(:backend_options, %{})
        |> maybe_put_boot_spec(target_preference)
        |> maybe_put_model_identity(request)

      InstanceSpec.new(
        backend: backend,
        startup_kind: optional_target_preference_field(target_preference, :startup_kind),
        execution_surface:
          optional_target_preference_field(target_preference, :execution_surface),
        backend_options: backend_options,
        metadata: metadata
      )
    end
  end

  defp fetch_target_preference(request) do
    case get_value(request, :target_preference) do
      %{} = target_preference -> {:ok, Map.new(target_preference)}
      nil -> {:error, {:missing_request_field, :target_preference}}
      other -> {:error, {:invalid_target_preference, other}}
    end
  end

  defp fetch_target_preference_field(target_preference, field) do
    case get_value(target_preference, field) do
      nil -> {:error, {:missing_target_preference, field}}
      value -> {:ok, value}
    end
  end

  defp optional_target_preference_field(target_preference, field) do
    get_value(target_preference, field)
  end

  defp optional_target_preference_map(target_preference, field, default) do
    case get_value(target_preference, field) do
      nil -> default
      %{} = value -> Map.new(value)
      value -> raise ArgumentError, "#{field} must be a map, got: #{inspect(value)}"
    end
  end

  defp maybe_put_boot_spec(backend_options, target_preference) do
    case get_value(target_preference, :boot_spec) do
      nil -> backend_options
      boot_spec -> Map.put_new(backend_options, :boot_spec, boot_spec)
    end
  end

  defp maybe_put_model_identity(backend_options, request) do
    case {Map.has_key?(backend_options, :model_identity), request_model_identity(request)} do
      {true, _model_identity} ->
        backend_options

      {false, nil} ->
        backend_options

      {false, model_identity} ->
        Map.put(backend_options, :model_identity, model_identity)
    end
  end

  defp request_model_identity(request) do
    request
    |> get_value(:model_preference, %{})
    |> get_value(:id, get_value(get_value(request, :model_preference, %{}), :model))
  end

  defp context_metadata(request, context) do
    context = Map.new(context)

    %{}
    |> put_optional_metadata(:request_id, get_value(request, :request_id))
    |> put_optional_metadata(:run_id, get_value(context, :run_id))
    |> put_optional_metadata(:attempt_id, get_value(context, :attempt_id))
    |> put_optional_metadata(:boundary_ref, get_value(context, :boundary_ref))
    |> put_optional_metadata(
      :trace_id,
      get_value(get_value(context, :observability, %{}), :trace_id)
    )
  end

  defp put_optional_metadata(metadata, _field, nil), do: metadata
  defp put_optional_metadata(metadata, field, value), do: Map.put(metadata, field, value)

  defp get_value(map, field, default \\ nil) when is_map(map) do
    Map.get(map, field, Map.get(map, Atom.to_string(field), default))
  end

  defp await_timeout(opts) do
    Keyword.get(opts, :await_timeout_ms, 5_000)
  end

  defp validate_startup_plan(
         %InstanceSpec{} = spec,
         backend_module,
         %Backend.StartupPlan{} = plan
       ) do
    manifest = backend_module.manifest()

    with :ok <- validate_requested_startup_kind(spec, plan),
         :ok <- validate_manifest_startup_kind(manifest, plan),
         :ok <- validate_management_mode(plan),
         :ok <- validate_transport_ownership(plan),
         :ok <- validate_execution_surface_support(spec, manifest, plan) do
      validate_manifest_management_mode(manifest, plan)
    end
  end

  defp validate_requested_startup_kind(
         %InstanceSpec{startup_kind: nil},
         %Backend.StartupPlan{}
       ),
       do: :ok

  defp validate_requested_startup_kind(
         %InstanceSpec{startup_kind: requested_startup_kind},
         %Backend.StartupPlan{startup_kind: requested_startup_kind}
       ),
       do: :ok

  defp validate_requested_startup_kind(
         %InstanceSpec{startup_kind: requested_startup_kind},
         %Backend.StartupPlan{startup_kind: actual_startup_kind}
       ) do
    {:error,
     {:invalid_startup_plan,
      {:requested_startup_kind_mismatch, requested_startup_kind, actual_startup_kind}}}
  end

  defp validate_manifest_startup_kind(
         %BackendManifest{startup_kind: nil},
         %Backend.StartupPlan{}
       ),
       do: :ok

  defp validate_manifest_startup_kind(
         %BackendManifest{startup_kind: startup_kind},
         %Backend.StartupPlan{startup_kind: startup_kind}
       ),
       do: :ok

  defp validate_manifest_startup_kind(
         %BackendManifest{startup_kind: declared_startup_kind, backend: backend},
         %Backend.StartupPlan{startup_kind: actual_startup_kind}
       ) do
    {:error,
     {:invalid_startup_plan,
      {:manifest_startup_kind_mismatch, backend, declared_startup_kind, actual_startup_kind}}}
  end

  defp validate_management_mode(%Backend.StartupPlan{
         startup_kind: :spawned,
         management_mode: :jido_managed
       }),
       do: :ok

  defp validate_management_mode(%Backend.StartupPlan{
         startup_kind: :attach_existing_service,
         management_mode: :externally_managed
       }),
       do: :ok

  defp validate_management_mode(%Backend.StartupPlan{
         startup_kind: startup_kind,
         management_mode: management_mode
       }) do
    {:error, {:invalid_startup_plan, {:management_mode_mismatch, startup_kind, management_mode}}}
  end

  defp validate_transport_ownership(%Backend.StartupPlan{
         startup_kind: :spawned,
         transport: %Backend.TransportPlan{}
       }),
       do: :ok

  defp validate_transport_ownership(%Backend.StartupPlan{
         startup_kind: :spawned,
         backend: backend
       }) do
    {:error, {:invalid_startup_plan, {:spawned_requires_transport, backend}}}
  end

  defp validate_transport_ownership(%Backend.StartupPlan{}), do: :ok

  defp validate_execution_surface_support(
         %InstanceSpec{} = spec,
         %BackendManifest{backend: backend, supported_surfaces: supported_surfaces},
         %Backend.StartupPlan{} = plan
       ) do
    surface_kind = resolved_surface_kind(spec, plan)

    if surface_kind in supported_surfaces do
      :ok
    else
      {:error,
       {:invalid_startup_plan,
        {:unsupported_execution_surface, backend, surface_kind, supported_surfaces}}}
    end
  end

  defp validate_manifest_management_mode(
         %BackendManifest{backend: backend, management_modes: management_modes},
         %Backend.StartupPlan{management_mode: management_mode}
       ) do
    if management_mode in management_modes do
      :ok
    else
      {:error,
       {:invalid_startup_plan,
        {:manifest_management_mode_mismatch, backend, management_modes, management_mode}}}
    end
  end

  defp resolved_surface_kind(
         %InstanceSpec{execution_surface: spec_surface},
         %Backend.StartupPlan{transport: transport}
       ) do
    case transport_surface_kind(transport) do
      nil -> execution_surface_kind(spec_surface)
      surface_kind -> surface_kind
    end
  end

  defp transport_surface_kind(%Backend.TransportPlan{execution_surface: execution_surface}),
    do: execution_surface_kind(execution_surface)

  defp transport_surface_kind(nil), do: nil

  defp execution_surface_kind(nil), do: :local_subprocess

  defp execution_surface_kind(%ExternalRuntimeTransport.ExecutionSurface{
         surface_kind: surface_kind
       }),
       do: surface_kind

  defp execution_surface_kind(surface) when is_list(surface),
    do: Keyword.get(surface, :surface_kind, :local_subprocess)

  defp execution_surface_kind(_surface), do: :local_subprocess
end
