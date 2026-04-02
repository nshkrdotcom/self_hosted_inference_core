defmodule SelfHostedInferenceCore.LeaseRef do
  @moduledoc """
  Shared lease identity contract for reusable runtime endpoints.
  """

  defstruct contract_version: "inference.v1",
            lease_ref: nil,
            owner_ref: nil,
            ttl_ms: nil,
            renewable?: true,
            metadata: %{}

  @type t :: %__MODULE__{
          contract_version: String.t(),
          lease_ref: String.t(),
          owner_ref: String.t() | nil,
          ttl_ms: non_neg_integer() | nil,
          renewable?: boolean(),
          metadata: map()
        }

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    {:ok,
     struct(__MODULE__, %{
       lease_ref: Map.get(attrs, :lease_ref, Map.get(attrs, "lease_ref")),
       owner_ref: Map.get(attrs, :owner_ref, Map.get(attrs, "owner_ref")),
       ttl_ms: Map.get(attrs, :ttl_ms, Map.get(attrs, "ttl_ms")),
       renewable?: Map.get(attrs, :renewable?, Map.get(attrs, "renewable?", true)),
       metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
     })}
  end

  def new(_attrs), do: {:error, :invalid_lease_ref}

  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, %__MODULE__{} = lease_ref} -> lease_ref
      {:error, reason} -> raise ArgumentError, "invalid lease ref: #{inspect(reason)}"
    end
  end
end
