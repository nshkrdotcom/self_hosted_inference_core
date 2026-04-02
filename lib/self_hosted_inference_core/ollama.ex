defmodule SelfHostedInferenceCore.Ollama do
  @moduledoc """
  Built-in `ollama` attach adapter for `self_hosted_inference_core`.

  This module keeps `ollama` as an `:attach_existing_service` backend inside
  the shared kernel until a separate package is justified by real lifecycle or
  release pressure.
  """

  alias SelfHostedInferenceCore.{
    BackendManifest,
    ConsumerManifest,
    InstanceSpec
  }

  alias SelfHostedInferenceCore.Ollama.{AttachSpec, Backend}

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

  @spec backend_id() :: :ollama
  def backend_id, do: :ollama

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

  @spec attach_spec(AttachSpec.t() | keyword() | map()) ::
          {:ok, AttachSpec.t()} | {:error, term()}
  def attach_spec(%AttachSpec{} = spec), do: {:ok, spec}
  def attach_spec(attrs) when is_list(attrs) or is_map(attrs), do: AttachSpec.new(attrs)

  @spec attach_spec!(AttachSpec.t() | keyword() | map()) :: AttachSpec.t()
  def attach_spec!(%AttachSpec{} = spec), do: spec
  def attach_spec!(attrs), do: AttachSpec.new!(attrs)

  @spec instance_spec(AttachSpec.t() | keyword() | map()) ::
          {:ok, InstanceSpec.t()} | {:error, term()}
  def instance_spec(spec_or_attrs) do
    with {:ok, %AttachSpec{} = spec} <- attach_spec(spec_or_attrs) do
      {:ok,
       InstanceSpec.new!(
         backend: backend_id(),
         startup_kind: :attach_existing_service,
         execution_surface: spec.execution_surface,
         backend_options: %{attach_spec: spec},
         metadata: spec.metadata
       )}
    end
  end

  @spec ensure_instance(AttachSpec.t() | keyword() | map(), keyword()) ::
          {:ok, SelfHostedInferenceCore.ensure_result()} | {:error, term()}
  def ensure_instance(spec_or_attrs, opts \\ []) do
    with {:ok, %InstanceSpec{} = instance_spec} <- instance_spec(spec_or_attrs) do
      SelfHostedInferenceCore.ensure_instance(instance_spec, opts)
    end
  end

  @spec resolve_endpoint(AttachSpec.t() | keyword() | map(), ConsumerManifest.t(), keyword()) ::
          {:ok, SelfHostedInferenceCore.resolve_result()} | {:error, term()}
  def resolve_endpoint(spec_or_attrs, %ConsumerManifest{} = consumer_manifest, opts \\ []) do
    with {:ok, %InstanceSpec{} = instance_spec} <- instance_spec(spec_or_attrs) do
      SelfHostedInferenceCore.resolve_endpoint(instance_spec, consumer_manifest, opts)
    end
  end

  @spec compatibility(ConsumerManifest.t()) :: SelfHostedInferenceCore.CompatibilityResult.t()
  def compatibility(%ConsumerManifest{} = consumer_manifest) do
    SelfHostedInferenceCore.compatibility(backend_id(), consumer_manifest)
  end

  @spec publish_endpoint(String.t()) ::
          {:ok, SelfHostedInferenceCore.EndpointDescriptor.t()} | {:error, term()}
  def publish_endpoint(instance_id) when is_binary(instance_id) do
    SelfHostedInferenceCore.publish_endpoint(instance_id)
  end
end
