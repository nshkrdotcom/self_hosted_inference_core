defmodule SelfHostedInferenceCore.InstanceSpec do
  @moduledoc """
  Input contract for ensuring or resolving a self-hosted runtime instance.
  """

  alias SelfHostedInferenceCore.AdapterRef

  defstruct contract_version: "inference.v1",
            backend: nil,
            adapter_ref: nil,
            startup_kind: nil,
            execution_surface: nil,
            backend_options: %{},
            metadata: %{}

  @type t :: %__MODULE__{
          contract_version: String.t(),
          backend: atom(),
          adapter_ref: AdapterRef.t() | nil,
          startup_kind: :spawned | :attach_existing_service | nil,
          execution_surface: keyword() | map() | ExecutionPlane.Placements.Surface.t() | nil,
          backend_options: map(),
          metadata: map()
        }

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    with {:ok, adapter_ref} <- AdapterRef.new(get_value(attrs, :adapter_ref)) do
      {:ok,
       struct(__MODULE__, %{
         backend: get_value(attrs, :backend),
         adapter_ref: adapter_ref,
         startup_kind: get_value(attrs, :startup_kind),
         execution_surface: get_value(attrs, :execution_surface),
         backend_options: get_value(attrs, :backend_options, %{}),
         metadata: get_value(attrs, :metadata, %{})
       })}
    end
  end

  def new(_attrs), do: {:error, :invalid_instance_spec}

  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, %__MODULE__{} = spec} -> spec
      {:error, reason} -> raise ArgumentError, "invalid instance spec: #{inspect(reason)}"
    end
  end

  @spec backend_id(t()) :: atom()
  def backend_id(%__MODULE__{backend: backend}), do: backend

  @spec adapter_ref(t()) :: AdapterRef.t() | nil
  def adapter_ref(%__MODULE__{adapter_ref: adapter_ref}), do: adapter_ref

  @spec registry_key(t()) :: {atom(), AdapterRef.key() | nil}
  def registry_key(%__MODULE__{} = spec),
    do: {backend_id(spec), AdapterRef.key(adapter_ref(spec))}

  defp get_value(attrs, field, default \\ nil) do
    Map.get(attrs, field, Map.get(attrs, Atom.to_string(field), default))
  end
end
