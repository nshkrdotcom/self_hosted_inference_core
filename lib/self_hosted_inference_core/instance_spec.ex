defmodule SelfHostedInferenceCore.InstanceSpec do
  @moduledoc """
  Input contract for ensuring or resolving a self-hosted runtime instance.
  """

  defstruct contract_version: "inference.v1",
            backend: nil,
            startup_kind: nil,
            execution_surface: nil,
            backend_options: %{},
            metadata: %{}

  @type t :: %__MODULE__{
          contract_version: String.t(),
          backend: atom(),
          startup_kind: :spawned | :attach_existing_service | nil,
          execution_surface: keyword() | ExternalRuntimeTransport.ExecutionSurface.t() | nil,
          backend_options: map(),
          metadata: map()
        }

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    {:ok,
     struct(__MODULE__, %{
       backend: Map.get(attrs, :backend, Map.get(attrs, "backend")),
       startup_kind: Map.get(attrs, :startup_kind, Map.get(attrs, "startup_kind")),
       execution_surface: Map.get(attrs, :execution_surface, Map.get(attrs, "execution_surface")),
       backend_options: Map.get(attrs, :backend_options, Map.get(attrs, "backend_options", %{})),
       metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
     })}
  end

  def new(_attrs), do: {:error, :invalid_instance_spec}

  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, %__MODULE__{} = spec} -> spec
      {:error, reason} -> raise ArgumentError, "invalid instance spec: #{inspect(reason)}"
    end
  end
end
