defmodule SelfHostedInferenceCore.Simulation do
  @moduledoc """
  Built-in configured backend for service-mode self-hosted inference simulation.

  This backend is selected by registering `SelfHostedInferenceCore.Simulation`
  and installing a `:simulation_backend` application configuration. It uses
  Execution Plane's `:lower_simulation` process transport and never launches a
  real backend process.
  """

  alias SelfHostedInferenceCore.{
    BackendManifest,
    ConsumerManifest,
    InstanceSpec
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
    attrs = Map.new(attrs)

    InstanceSpec.new(
      backend: backend_id(),
      startup_kind: :spawned,
      execution_surface: Map.get(attrs, :execution_surface, Map.get(attrs, "execution_surface")),
      backend_options: Map.get(attrs, :backend_options, Map.get(attrs, "backend_options", %{})),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    )
  end

  @spec ensure_instance(keyword() | map(), keyword()) ::
          {:ok, SelfHostedInferenceCore.ensure_result()} | {:error, term()}
  def ensure_instance(attrs \\ [], opts \\ []) do
    with {:ok, %InstanceSpec{} = instance_spec} <- instance_spec(attrs) do
      SelfHostedInferenceCore.ensure_instance(instance_spec, opts)
    end
  end

  @spec resolve_endpoint(keyword() | map(), ConsumerManifest.t(), keyword()) ::
          {:ok, SelfHostedInferenceCore.resolve_result()} | {:error, term()}
  def resolve_endpoint(attrs, %ConsumerManifest{} = consumer_manifest, opts \\ []) do
    with {:ok, %InstanceSpec{} = instance_spec} <- instance_spec(attrs) do
      SelfHostedInferenceCore.resolve_endpoint(instance_spec, consumer_manifest, opts)
    end
  end

  @spec compatibility(ConsumerManifest.t()) :: SelfHostedInferenceCore.CompatibilityResult.t()
  def compatibility(%ConsumerManifest{} = consumer_manifest) do
    SelfHostedInferenceCore.compatibility(backend_id(), consumer_manifest)
  end
end
