defmodule SelfHostedInferenceCore.AdapterRef do
  @moduledoc """
  Stable identifier for a backend-specific model adapter.

  Runtime instances remain addressable by their backend-produced instance id.
  Adapter refs add a second lookup key so one backend can host multiple adapter
  contracts without conflating their lifecycle.
  """

  @enforce_keys [:id, :version, :contract]
  defstruct [:id, :version, :contract]

  @type key :: {atom(), String.t(), atom()}

  @type t :: %__MODULE__{
          id: atom(),
          version: String.t(),
          contract: atom()
        }

  @spec new(keyword() | map() | t() | nil) :: {:ok, t() | nil} | {:error, term()}
  def new(nil), do: {:ok, nil}
  def new(%__MODULE__{} = adapter_ref), do: {:ok, adapter_ref}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    with {:ok, id} <- normalize_atom(fetch(attrs, :id), :id),
         {:ok, version} <- normalize_version(fetch(attrs, :version)),
         {:ok, contract} <- normalize_atom(fetch(attrs, :contract), :contract) do
      {:ok, %__MODULE__{id: id, version: version, contract: contract}}
    end
  end

  def new(attrs), do: {:error, {:invalid_adapter_ref, attrs}}

  @spec new!(keyword() | map() | t() | nil) :: t() | nil
  def new!(attrs) do
    case new(attrs) do
      {:ok, adapter_ref} -> adapter_ref
      {:error, reason} -> raise ArgumentError, "invalid adapter_ref: #{inspect(reason)}"
    end
  end

  @spec key(t() | key() | nil) :: key() | nil
  def key(nil), do: nil
  def key(%__MODULE__{id: id, version: version, contract: contract}), do: {id, version, contract}
  def key({id, version, contract}), do: {id, version, contract}

  defp fetch(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

  defp normalize_atom(value, _field) when is_atom(value), do: {:ok, value}
  defp normalize_atom(value, field), do: {:error, {:invalid_adapter_ref_field, field, value}}

  defp normalize_version(version) when is_binary(version) do
    version = String.trim(version)

    if version == "" do
      {:error, {:invalid_adapter_ref_field, :version, version}}
    else
      {:ok, version}
    end
  end

  defp normalize_version(version), do: {:error, {:invalid_adapter_ref_field, :version, version}}
end
