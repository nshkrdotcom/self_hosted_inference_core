defmodule SelfHostedInferenceCore.CompatibilityResult do
  @moduledoc """
  Shared compatibility result contract for runtime endpoint selection.
  """

  defstruct contract_version: "inference.v1",
            compatible?: false,
            reason: :unresolved,
            resolved_runtime_kind: nil,
            resolved_management_mode: nil,
            resolved_protocol: nil,
            warnings: [],
            missing_requirements: [],
            metadata: %{}

  @type t :: %__MODULE__{
          contract_version: String.t(),
          compatible?: boolean(),
          reason: atom(),
          resolved_runtime_kind: atom() | nil,
          resolved_management_mode: atom() | nil,
          resolved_protocol: atom() | nil,
          warnings: [atom()],
          missing_requirements: [atom()],
          metadata: map()
        }

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    {:ok,
     struct(__MODULE__, %{
       compatible?: Map.get(attrs, :compatible?, Map.get(attrs, "compatible?", false)),
       reason: Map.get(attrs, :reason, Map.get(attrs, "reason", :unresolved)),
       resolved_runtime_kind:
         Map.get(attrs, :resolved_runtime_kind, Map.get(attrs, "resolved_runtime_kind")),
       resolved_management_mode:
         Map.get(attrs, :resolved_management_mode, Map.get(attrs, "resolved_management_mode")),
       resolved_protocol: Map.get(attrs, :resolved_protocol, Map.get(attrs, "resolved_protocol")),
       warnings: Map.get(attrs, :warnings, Map.get(attrs, "warnings", [])),
       missing_requirements:
         Map.get(attrs, :missing_requirements, Map.get(attrs, "missing_requirements", [])),
       metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
     })}
  end

  def new(_attrs), do: {:error, :invalid_compatibility_result}

  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, %__MODULE__{} = result} -> result
      {:error, reason} -> raise ArgumentError, "invalid compatibility result: #{inspect(reason)}"
    end
  end
end
