defmodule SelfHostedInferenceCore.EndpointDescriptor do
  @moduledoc """
  Shared endpoint publication contract for execution-ready self-hosted endpoints.
  """

  defstruct contract_version: "inference.v1",
            endpoint_id: nil,
            runtime_kind: :service,
            management_mode: nil,
            target_class: :self_hosted_endpoint,
            protocol: :openai_chat_completions,
            base_url: nil,
            headers: %{},
            provider_identity: nil,
            model_identity: nil,
            source_runtime: nil,
            source_runtime_ref: nil,
            lease_ref: nil,
            health_ref: nil,
            boundary_ref: nil,
            capabilities: %{},
            metadata: %{}

  @type t :: %__MODULE__{
          contract_version: String.t(),
          endpoint_id: String.t(),
          runtime_kind: :client | :task | :service,
          management_mode: atom(),
          target_class: :cloud_provider | :cli_endpoint | :self_hosted_endpoint,
          protocol: atom(),
          base_url: String.t(),
          headers: %{optional(String.t()) => String.t()},
          provider_identity: atom() | String.t() | nil,
          model_identity: String.t() | nil,
          source_runtime: atom(),
          source_runtime_ref: String.t() | nil,
          lease_ref: String.t() | nil,
          health_ref: String.t() | nil,
          boundary_ref: String.t() | nil,
          capabilities: map(),
          metadata: map()
        }

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    {:ok,
     struct(__MODULE__, %{
       endpoint_id: Map.get(attrs, :endpoint_id, Map.get(attrs, "endpoint_id")),
       runtime_kind: Map.get(attrs, :runtime_kind, Map.get(attrs, "runtime_kind", :service)),
       management_mode: Map.get(attrs, :management_mode, Map.get(attrs, "management_mode")),
       target_class:
         Map.get(attrs, :target_class, Map.get(attrs, "target_class", :self_hosted_endpoint)),
       protocol: Map.get(attrs, :protocol, Map.get(attrs, "protocol", :openai_chat_completions)),
       base_url: Map.get(attrs, :base_url, Map.get(attrs, "base_url")),
       headers: Map.get(attrs, :headers, Map.get(attrs, "headers", %{})),
       provider_identity: Map.get(attrs, :provider_identity, Map.get(attrs, "provider_identity")),
       model_identity: Map.get(attrs, :model_identity, Map.get(attrs, "model_identity")),
       source_runtime: Map.get(attrs, :source_runtime, Map.get(attrs, "source_runtime")),
       source_runtime_ref:
         Map.get(attrs, :source_runtime_ref, Map.get(attrs, "source_runtime_ref")),
       lease_ref: Map.get(attrs, :lease_ref, Map.get(attrs, "lease_ref")),
       health_ref: Map.get(attrs, :health_ref, Map.get(attrs, "health_ref")),
       boundary_ref: Map.get(attrs, :boundary_ref, Map.get(attrs, "boundary_ref")),
       capabilities: Map.get(attrs, :capabilities, Map.get(attrs, "capabilities", %{})),
       metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
     })}
  end

  def new(_attrs), do: {:error, :invalid_endpoint_descriptor}

  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, %__MODULE__{} = descriptor} -> descriptor
      {:error, reason} -> raise ArgumentError, "invalid endpoint descriptor: #{inspect(reason)}"
    end
  end
end
