defmodule SelfHostedInferenceCore.ConsumerManifest do
  @moduledoc """
  Shared consumer manifest contract for endpoint compatibility checks.
  """

  defstruct contract_version: "inference.v1",
            consumer: nil,
            accepted_runtime_kinds: [:service],
            accepted_management_modes: [],
            accepted_protocols: [:openai_chat_completions],
            required_capabilities: %{},
            optional_capabilities: %{},
            constraints: %{},
            metadata: %{}

  @type t :: %__MODULE__{
          contract_version: String.t(),
          consumer: atom(),
          accepted_runtime_kinds: [atom()],
          accepted_management_modes: [atom()],
          accepted_protocols: [atom()],
          required_capabilities: map(),
          optional_capabilities: map(),
          constraints: map(),
          metadata: map()
        }

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    {:ok,
     struct(__MODULE__, %{
       consumer: Map.get(attrs, :consumer, Map.get(attrs, "consumer")),
       accepted_runtime_kinds:
         Map.get(
           attrs,
           :accepted_runtime_kinds,
           Map.get(attrs, "accepted_runtime_kinds", [:service])
         ),
       accepted_management_modes:
         Map.get(
           attrs,
           :accepted_management_modes,
           Map.get(attrs, "accepted_management_modes", [])
         ),
       accepted_protocols:
         Map.get(
           attrs,
           :accepted_protocols,
           Map.get(attrs, "accepted_protocols", [:openai_chat_completions])
         ),
       required_capabilities:
         Map.get(attrs, :required_capabilities, Map.get(attrs, "required_capabilities", %{})),
       optional_capabilities:
         Map.get(attrs, :optional_capabilities, Map.get(attrs, "optional_capabilities", %{})),
       constraints: Map.get(attrs, :constraints, Map.get(attrs, "constraints", %{})),
       metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
     })}
  end

  def new(_attrs), do: {:error, :invalid_consumer_manifest}

  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, %__MODULE__{} = manifest} -> manifest
      {:error, reason} -> raise ArgumentError, "invalid consumer manifest: #{inspect(reason)}"
    end
  end
end
