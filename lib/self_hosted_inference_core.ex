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

  defp await_timeout(opts) do
    Keyword.get(opts, :await_timeout_ms, 5_000)
  end
end
