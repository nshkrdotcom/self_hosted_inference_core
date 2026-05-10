defmodule SelfHostedInferenceCore.Ollama.AttachSpec do
  @moduledoc """
  Typed attach contract for the built-in `ollama` backend.
  """

  alias SelfHostedInferenceCore.GovernedAuthority

  @default_root_url "http://127.0.0.1:11434"

  defstruct contract_version: "inference.v1",
            root_url: @default_root_url,
            model_identity: nil,
            api_key: nil,
            headers: %{},
            ollama_http: nil,
            ready_timeout_ms: 5_000,
            readiness_interval_ms: 100,
            health_interval_ms: 1_000,
            execution_surface: nil,
            metadata: %{}

  @type t :: %__MODULE__{
          contract_version: String.t(),
          root_url: String.t(),
          model_identity: String.t(),
          api_key: String.t() | nil,
          headers: map(),
          ollama_http:
            (atom(), String.t(), map() | nil, keyword() ->
               {:ok, pos_integer(), map()} | {:error, term()})
            | nil,
          ready_timeout_ms: pos_integer(),
          readiness_interval_ms: pos_integer(),
          health_interval_ms: pos_integer(),
          execution_surface: keyword() | map() | ExecutionPlane.Placements.Surface.t() | nil,
          metadata: map()
        }

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    with {:ok, attrs} <- maybe_materialize_governed_authority(attrs) do
      root_url =
        attrs
        |> get_value(:root_url, get_value(attrs, :base_url, default_root_url()))
        |> normalize_root_url()

      model_identity =
        attrs
        |> get_value(:model_identity, get_value(attrs, :model))
        |> validate_required_string(:model_identity)

      headers =
        attrs
        |> get_value(:headers, %{})
        |> normalize_headers()
        |> maybe_put_authorization(get_value(attrs, :api_key))

      {:ok,
       %__MODULE__{
         root_url: root_url,
         model_identity: model_identity,
         api_key: normalize_optional_string(get_value(attrs, :api_key)),
         headers: headers,
         ollama_http: get_value(attrs, :ollama_http),
         ready_timeout_ms: get_value(attrs, :ready_timeout_ms, 5_000),
         readiness_interval_ms: get_value(attrs, :readiness_interval_ms, 100),
         health_interval_ms: get_value(attrs, :health_interval_ms, 1_000),
         execution_surface: get_value(attrs, :execution_surface),
         metadata: Map.new(get_value(attrs, :metadata, %{}))
       }}
    end
  rescue
    error in ArgumentError -> {:error, error.message}
  end

  def new(_attrs), do: {:error, :invalid_attach_spec}

  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, %__MODULE__{} = spec} -> spec
      {:error, reason} -> raise ArgumentError, "invalid ollama attach spec: #{inspect(reason)}"
    end
  end

  @spec base_url(t()) :: String.t()
  def base_url(%__MODULE__{root_url: root_url}), do: root_url <> "/v1"

  @spec health_url(t()) :: String.t()
  def health_url(%__MODULE__{root_url: root_url}), do: root_url <> "/api/version"

  @spec instance_key(t()) :: String.t()
  def instance_key(%__MODULE__{} = spec) do
    identity =
      %{
        root_url: spec.root_url,
        model_identity: spec.model_identity,
        headers_fingerprint: fingerprint(spec.headers),
        execution_surface: execution_surface_identity(spec.execution_surface)
      }
      |> :erlang.term_to_binary()
      |> Base.url_encode64(padding: false)

    "ollama:" <> identity
  end

  @spec default_root_url() :: String.t()
  def default_root_url do
    :self_hosted_inference_core
    |> Application.get_env(:ollama_root_url, @default_root_url)
    |> normalize_root_url()
  end

  defp get_value(map, field, default \\ nil) when is_map(map) do
    Map.get(map, field, Map.get(map, Atom.to_string(field), default))
  end

  defp maybe_materialize_governed_authority(attrs) do
    case GovernedAuthority.fetch(attrs) do
      :error ->
        {:ok, attrs}

      {:ok, authority} ->
        with :ok <- GovernedAuthority.reject_unmanaged_attach_attrs(attrs) do
          {:ok, GovernedAuthority.materialize_attach_attrs(authority, attrs)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_root_url(value) when is_binary(value) do
    value
    |> String.trim()
    |> then(fn
      "" ->
        @default_root_url

      <<"http://", _::binary>> = url ->
        normalize_root_uri(url)

      <<"https://", _::binary>> = url ->
        normalize_root_uri(url)

      url ->
        normalize_root_uri("http://" <> url)
    end)
  end

  defp normalize_root_uri(url) do
    uri = URI.parse(url)

    trimmed_path = String.trim_trailing(uri.path || "", "/")

    path =
      cond do
        trimmed_path == "" ->
          nil

        trimmed_path == "/v1" ->
          nil

        String.ends_with?(trimmed_path, "/v1") ->
          String.replace_suffix(trimmed_path, "/v1", "")

        true ->
          trimmed_path
      end

    %{uri | path: path, query: nil, fragment: nil}
    |> URI.to_string()
    |> String.trim_trailing("/")
  end

  defp validate_required_string(nil, field), do: raise(ArgumentError, "#{field} is required")

  defp validate_required_string(value, field) do
    case normalize_optional_string(value) do
      nil -> raise ArgumentError, "#{field} is required"
      normalized -> normalized
    end
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_headers(headers) when is_map(headers) do
    Enum.into(headers, %{}, fn {key, value} ->
      {String.downcase(to_string(key)), to_string(value)}
    end)
  end

  defp normalize_headers(_headers), do: %{}

  defp maybe_put_authorization(headers, nil), do: headers

  defp maybe_put_authorization(headers, api_key) do
    Map.put(headers, "authorization", "Bearer " <> String.trim(to_string(api_key)))
  end

  defp fingerprint(value) do
    value
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end

  defp execution_surface_identity(%ExecutionPlane.Placements.Surface{} = surface) do
    %{
      surface_kind: normalize_surface_kind(surface.surface_kind),
      surface_ref: surface.surface_ref,
      target_id: surface.target_id
    }
  end

  defp execution_surface_identity(surface) when is_list(surface) do
    %{
      surface_kind: Keyword.get(surface, :surface_kind, :local_subprocess),
      surface_ref: Keyword.get(surface, :surface_ref),
      target_id: Keyword.get(surface, :target_id)
    }
  end

  defp execution_surface_identity(surface) when is_map(surface) do
    %{
      surface_kind:
        surface
        |> Map.get(:surface_kind, Map.get(surface, "surface_kind", :local_subprocess))
        |> normalize_surface_kind(),
      surface_ref: Map.get(surface, :surface_ref, Map.get(surface, "surface_ref")),
      target_id: Map.get(surface, :target_id, Map.get(surface, "target_id"))
    }
  end

  defp execution_surface_identity(_surface), do: %{surface_kind: :local_subprocess}

  defp normalize_surface_kind("local_subprocess"), do: :local_subprocess
  defp normalize_surface_kind("ssh_exec"), do: :ssh_exec
  defp normalize_surface_kind("guest_bridge"), do: :guest_bridge
  defp normalize_surface_kind(surface_kind) when is_atom(surface_kind), do: surface_kind
  defp normalize_surface_kind(_surface_kind), do: :local_subprocess
end
