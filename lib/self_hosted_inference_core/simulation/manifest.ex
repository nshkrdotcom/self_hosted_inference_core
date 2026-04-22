defmodule SelfHostedInferenceCore.Simulation.Manifest do
  @moduledoc """
  Configured self-hosted inference simulation backend manifest.

  The manifest is selected from application configuration by the simulation
  backend. Normal production callers do not pass a public `simulation:` option.
  """

  @contract_version "self_hosted_simulation_manifest.v1"
  @supported_health_statuses [:healthy, :degraded, :unavailable]
  @default_protocol :openai_chat_completions
  @default_provider_identity :self_hosted_simulation
  @default_capabilities %{streaming?: true, tool_calling?: false, embeddings?: false}
  @default_headers %{}
  @default_metadata %{}

  defstruct contract_version: @contract_version,
            manifest_ref: nil,
            scenario_ref: nil,
            endpoint_ref: nil,
            base_url: nil,
            protocol: @default_protocol,
            provider_identity: @default_provider_identity,
            model_identity: nil,
            health_status: :healthy,
            capabilities: @default_capabilities,
            headers: @default_headers,
            deterministic_response: nil,
            ready_timeout_ms: 1_000,
            readiness_interval_ms: 10,
            health_interval_ms: 50,
            metadata: @default_metadata

  @type t :: %__MODULE__{
          contract_version: String.t(),
          manifest_ref: String.t(),
          scenario_ref: String.t(),
          endpoint_ref: String.t(),
          base_url: String.t(),
          protocol: atom(),
          provider_identity: atom() | String.t(),
          model_identity: String.t(),
          health_status: :healthy | :degraded | :unavailable,
          capabilities: map(),
          headers: map(),
          deterministic_response: map(),
          ready_timeout_ms: pos_integer(),
          readiness_interval_ms: pos_integer(),
          health_interval_ms: pos_integer(),
          metadata: map()
        }

  @spec contract_version() :: String.t()
  def contract_version, do: @contract_version

  @spec fetch_active() :: {:ok, t()} | {:error, term()}
  def fetch_active do
    with {:ok, config} <- simulation_backend_config(),
         :ok <- reject_public_simulation_selector(config),
         {:ok, manifest_ref} <- required_string(config, :active_manifest_ref),
         {:ok, attrs} <- fetch_configured_manifest(config, manifest_ref),
         {:ok, manifest} <- new(Map.put_new(attrs, :manifest_ref, manifest_ref)),
         :ok <- validate_active_manifest_ref(manifest, manifest_ref) do
      {:ok, manifest}
    end
  end

  @spec new(t() | keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = manifest), do: validate(manifest)
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    with :ok <- reject_public_simulation_selector(attrs),
         {:ok, manifest_ref} <- required_string(attrs, :manifest_ref),
         {:ok, scenario_ref} <- required_string(attrs, :scenario_ref),
         {:ok, deterministic_response} <- deterministic_response(attrs),
         {:ok, base_url} <- base_url(attrs, manifest_ref),
         {:ok, protocol} <- atom_value(attrs, :protocol, @default_protocol),
         {:ok, provider_identity} <-
           provider_identity(attrs, @default_provider_identity),
         {:ok, model_identity} <- model_identity(attrs),
         {:ok, health_status} <- health_status(attrs),
         {:ok, capabilities} <- map_value(attrs, :capabilities, @default_capabilities),
         {:ok, headers} <- map_value(attrs, :headers, @default_headers),
         {:ok, metadata} <- map_value(attrs, :metadata, @default_metadata),
         {:ok, ready_timeout_ms} <- positive_integer(attrs, :ready_timeout_ms, 1_000),
         {:ok, readiness_interval_ms} <-
           positive_integer(attrs, :readiness_interval_ms, 10),
         {:ok, health_interval_ms} <- positive_integer(attrs, :health_interval_ms, 50) do
      validate(%__MODULE__{
        manifest_ref: manifest_ref,
        scenario_ref: scenario_ref,
        endpoint_ref: string_value(attrs, :endpoint_ref, manifest_ref),
        base_url: base_url,
        protocol: protocol,
        provider_identity: provider_identity,
        model_identity: model_identity,
        health_status: health_status,
        capabilities: capabilities,
        headers: headers,
        deterministic_response: deterministic_response,
        ready_timeout_ms: ready_timeout_ms,
        readiness_interval_ms: readiness_interval_ms,
        health_interval_ms: health_interval_ms,
        metadata: metadata
      })
    end
  end

  def new(attrs), do: {:error, {:invalid_simulation_manifest, attrs}}

  @spec new!(t() | keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, %__MODULE__{} = manifest} ->
        manifest

      {:error, reason} ->
        raise ArgumentError, "invalid simulation manifest: #{inspect(reason)}"
    end
  end

  @spec put_model_identity(t(), String.t() | nil) :: t()
  def put_model_identity(%__MODULE__{} = manifest, nil), do: manifest

  def put_model_identity(%__MODULE__{} = manifest, model_identity)
      when is_binary(model_identity) and model_identity != "" do
    %__MODULE__{manifest | model_identity: model_identity}
  end

  @spec deterministic_response_ref(t()) :: String.t()
  def deterministic_response_ref(%__MODULE__{deterministic_response: response}) do
    Map.fetch!(response, :response_ref)
  end

  defp simulation_backend_config do
    case Application.get_env(:self_hosted_inference_core, :simulation_backend) do
      nil -> {:error, {:simulation_backend_not_configured, :simulation_backend}}
      config when is_list(config) -> {:ok, Map.new(config)}
      config when is_map(config) -> {:ok, Map.new(config)}
      config -> {:error, {:invalid_simulation_backend_config, config}}
    end
  end

  defp reject_public_simulation_selector(values) do
    if Map.has_key?(values, :simulation) or Map.has_key?(values, "simulation") do
      {:error, {:public_simulation_selector_forbidden, :self_hosted_inference_core}}
    else
      :ok
    end
  end

  defp fetch_configured_manifest(config, manifest_ref) do
    case value(config, :manifests, %{}) do
      manifests when is_list(manifests) or is_map(manifests) ->
        manifests = Map.new(manifests)
        manifests |> lookup_manifest(manifest_ref) |> normalize_manifest_attrs(manifest_ref)

      other ->
        {:error, {:invalid_simulation_manifest_registry, other}}
    end
  end

  defp lookup_manifest(manifests, manifest_ref) do
    Map.get(manifests, manifest_ref) || Map.get(manifests, existing_atom(manifest_ref))
  end

  defp normalize_manifest_attrs(nil, manifest_ref) do
    {:error, {:simulation_manifest_not_configured, manifest_ref}}
  end

  defp normalize_manifest_attrs(%__MODULE__{} = manifest, _manifest_ref) do
    {:ok, Map.from_struct(manifest)}
  end

  defp normalize_manifest_attrs(attrs, _manifest_ref) when is_list(attrs) or is_map(attrs) do
    {:ok, Map.new(attrs)}
  end

  defp normalize_manifest_attrs(other, _manifest_ref) do
    {:error, {:invalid_simulation_manifest, other}}
  end

  defp validate_active_manifest_ref(%__MODULE__{manifest_ref: manifest_ref}, manifest_ref),
    do: :ok

  defp validate_active_manifest_ref(%__MODULE__{manifest_ref: actual}, expected) do
    {:error, {:simulation_manifest_ref_mismatch, expected, actual}}
  end

  defp validate(%__MODULE__{} = manifest) do
    cond do
      manifest.contract_version != @contract_version ->
        {:error, {:invalid_contract_version, manifest.contract_version}}

      manifest.health_status not in @supported_health_statuses ->
        {:error, {:invalid_health_status, manifest.health_status}}

      not is_map(manifest.deterministic_response) ->
        {:error, {:invalid_deterministic_response, manifest.deterministic_response}}

      true ->
        {:ok, manifest}
    end
  end

  defp deterministic_response(attrs) do
    case value(attrs, :deterministic_response) do
      response when is_list(response) or is_map(response) ->
        response = Map.new(response)

        with {:ok, response_ref} <- required_string(response, :response_ref),
             {:ok, body} <- map_value(response, :body, %{}),
             {:ok, usage} <- map_value(response, :usage, %{}),
             {:ok, metadata} <- map_value(response, :metadata, %{}) do
          {:ok,
           %{
             response_ref: response_ref,
             body: body,
             usage: usage,
             metadata: metadata
           }}
        end

      other ->
        {:error, {:invalid_deterministic_response, other}}
    end
  end

  defp base_url(attrs, manifest_ref) do
    case string_value(attrs, :base_url, nil) do
      nil ->
        {:ok, "http://127.0.0.1:65535/self-hosted-simulation/#{slug(manifest_ref)}/v1"}

      base_url ->
        {:ok, base_url}
    end
  end

  defp provider_identity(attrs, default) do
    case value(attrs, :provider_identity, default) do
      provider_identity when is_atom(provider_identity) ->
        {:ok, provider_identity}

      provider_identity when is_binary(provider_identity) and provider_identity != "" ->
        {:ok, provider_identity}

      other ->
        {:error, {:invalid_provider_identity, other}}
    end
  end

  defp model_identity(attrs) do
    case string_value(attrs, :model_identity, nil) do
      nil -> {:ok, "self-hosted-simulation-model"}
      model_identity -> {:ok, model_identity}
    end
  end

  defp health_status(attrs) do
    case atom_value(attrs, :health_status, :healthy) do
      {:ok, status} when status in @supported_health_statuses -> {:ok, status}
      {:ok, status} -> {:error, {:invalid_health_status, status}}
      {:error, _reason} = error -> error
    end
  end

  defp required_string(attrs, key) do
    case string_value(attrs, key, nil) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:missing_required_simulation_manifest_key, key}}
    end
  end

  defp string_value(attrs, key, default) do
    case value(attrs, key, default) do
      value when is_binary(value) -> value
      value when is_atom(value) -> Atom.to_string(value)
      nil -> nil
      _other -> default
    end
  end

  defp atom_value(attrs, key, default) do
    case value(attrs, key, default) do
      value when is_atom(value) -> {:ok, value}
      value when is_binary(value) and value != "" -> existing_atom_value(key, value)
      other -> {:error, {:invalid_atom_value, key, other}}
    end
  end

  defp map_value(attrs, key, default) do
    case value(attrs, key, default) do
      value when is_list(value) or is_map(value) -> {:ok, Map.new(value)}
      other -> {:error, {:invalid_map_value, key, other}}
    end
  end

  defp positive_integer(attrs, key, default) do
    case value(attrs, key, default) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      other -> {:error, {:invalid_positive_integer, key, other}}
    end
  end

  defp value(attrs, key, default \\ nil) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end

  defp existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  defp existing_atom_value(key, value) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> {:error, {:invalid_atom_value, key, value}}
  end

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/, "-")
    |> String.trim("-")
  end
end
