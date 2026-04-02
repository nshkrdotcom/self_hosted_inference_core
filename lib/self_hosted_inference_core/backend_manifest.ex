defmodule SelfHostedInferenceCore.BackendManifest do
  @moduledoc """
  Shared backend manifest contract for self-hosted runtimes.
  """

  defstruct contract_version: "inference.v1",
            backend: nil,
            runtime_kind: :service,
            management_modes: [],
            startup_kind: nil,
            protocols: [:openai_chat_completions],
            capabilities: %{},
            supported_surfaces: [],
            resource_profile: %{},
            metadata: %{}

  @type t :: %__MODULE__{
          contract_version: String.t(),
          backend: atom(),
          runtime_kind: :task | :service,
          management_modes: [atom()],
          startup_kind: atom() | nil,
          protocols: [atom()],
          capabilities: map(),
          supported_surfaces: [atom()],
          resource_profile: map(),
          metadata: map()
        }

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    {:ok,
     struct(__MODULE__, %{
       backend: Map.get(attrs, :backend, Map.get(attrs, "backend")),
       runtime_kind: Map.get(attrs, :runtime_kind, Map.get(attrs, "runtime_kind", :service)),
       management_modes:
         Map.get(attrs, :management_modes, Map.get(attrs, "management_modes", [])),
       startup_kind: Map.get(attrs, :startup_kind, Map.get(attrs, "startup_kind")),
       protocols:
         Map.get(attrs, :protocols, Map.get(attrs, "protocols", [:openai_chat_completions])),
       capabilities: Map.get(attrs, :capabilities, Map.get(attrs, "capabilities", %{})),
       supported_surfaces:
         Map.get(attrs, :supported_surfaces, Map.get(attrs, "supported_surfaces", [])),
       resource_profile:
         Map.get(attrs, :resource_profile, Map.get(attrs, "resource_profile", %{})),
       metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
     })}
  end

  def new(_attrs), do: {:error, :invalid_backend_manifest}

  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, %__MODULE__{} = manifest} -> manifest
      {:error, reason} -> raise ArgumentError, "invalid backend manifest: #{inspect(reason)}"
    end
  end
end
