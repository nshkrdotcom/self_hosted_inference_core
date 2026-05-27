defmodule SelfHostedInferenceCore.GovernedAuthority do
  @moduledoc """
  Authority-selected endpoint and attach materialization for governed services.
  """

  @required_refs [
    :endpoint_ref,
    :service_identity_ref,
    :provider_account_ref,
    :model_account_ref,
    :target_ref,
    :target_posture_ref,
    :attach_grant_ref,
    :operation_policy_ref,
    :redaction_ref
  ]

  @optional_refs [
    :credential_ref,
    :credential_lease_ref
  ]

  @unmanaged_attach_fields [
    :root_url,
    :base_url,
    :model_identity,
    :model,
    :api_key,
    :headers,
    :ollama_http,
    :execution_surface,
    :metadata
  ]

  @unmanaged_target_preference_fields [
    :backend,
    :startup_kind,
    :execution_surface,
    :backend_options,
    :boot_spec,
    :attach_spec,
    :metadata,
    :target_class,
    :root_url,
    :base_url,
    :model_identity,
    :model,
    :api_key,
    :headers
  ]

  @enforce_keys [:backend, :root_url, :model_identity] ++ @required_refs
  defstruct backend: nil,
            startup_kind: :attach_existing_service,
            endpoint_ref: nil,
            service_identity_ref: nil,
            provider_account_ref: nil,
            model_account_ref: nil,
            target_ref: nil,
            target_posture_ref: nil,
            attach_grant_ref: nil,
            operation_policy_ref: nil,
            redaction_ref: nil,
            credential_ref: nil,
            credential_lease_ref: nil,
            root_url: nil,
            model_identity: nil,
            api_key: nil,
            headers: %{},
            ollama_http: nil,
            ready_timeout_ms: 5_000,
            readiness_interval_ms: 100,
            health_interval_ms: 1_000,
            execution_surface: nil,
            backend_options: %{},
            metadata: %{}

  @type t :: %__MODULE__{
          backend: atom() | String.t(),
          startup_kind: :spawned | :attach_existing_service | nil,
          endpoint_ref: String.t(),
          service_identity_ref: String.t(),
          provider_account_ref: String.t(),
          model_account_ref: String.t(),
          target_ref: String.t(),
          target_posture_ref: String.t(),
          attach_grant_ref: String.t(),
          operation_policy_ref: String.t(),
          redaction_ref: String.t(),
          credential_ref: String.t() | nil,
          credential_lease_ref: String.t() | nil,
          root_url: String.t(),
          model_identity: String.t(),
          api_key: String.t() | nil,
          headers: map(),
          ollama_http: (atom(), String.t(), map() | nil, keyword() -> term()) | nil,
          ready_timeout_ms: pos_integer(),
          readiness_interval_ms: pos_integer(),
          health_interval_ms: pos_integer(),
          execution_surface: keyword() | map() | nil,
          backend_options: map(),
          metadata: map()
        }

  @spec new(t() | keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = authority), do: validate(authority)

  def new(attrs) when is_list(attrs) do
    attrs
    |> Enum.into(%{})
    |> new()
  end

  def new(attrs) when is_map(attrs) do
    authority = %__MODULE__{
      backend: value(attrs, :backend),
      startup_kind: value(attrs, :startup_kind, :attach_existing_service),
      endpoint_ref: value(attrs, :endpoint_ref),
      service_identity_ref: value(attrs, :service_identity_ref),
      provider_account_ref: value(attrs, :provider_account_ref),
      model_account_ref: value(attrs, :model_account_ref),
      target_ref: value(attrs, :target_ref),
      target_posture_ref: value(attrs, :target_posture_ref),
      attach_grant_ref: value(attrs, :attach_grant_ref),
      operation_policy_ref: value(attrs, :operation_policy_ref),
      redaction_ref: value(attrs, :redaction_ref),
      credential_ref: value(attrs, :credential_ref),
      credential_lease_ref: value(attrs, :credential_lease_ref),
      root_url: value(attrs, :root_url),
      model_identity: value(attrs, :model_identity, value(attrs, :model)),
      api_key: value(attrs, :api_key),
      headers: value(attrs, :headers, %{}),
      ollama_http: value(attrs, :ollama_http),
      ready_timeout_ms: value(attrs, :ready_timeout_ms, 5_000),
      readiness_interval_ms: value(attrs, :readiness_interval_ms, 100),
      health_interval_ms: value(attrs, :health_interval_ms, 1_000),
      execution_surface: value(attrs, :execution_surface),
      backend_options: value(attrs, :backend_options, %{}),
      metadata: value(attrs, :metadata, %{})
    }

    validate(authority)
  end

  def new(_attrs), do: {:error, :invalid_governed_authority}

  @spec new!(t() | keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, authority} ->
        authority

      {:error, reason} ->
        raise ArgumentError, "invalid self-hosted governed authority: #{inspect(reason)}"
    end
  end

  @spec fetch(keyword() | map()) :: {:ok, t()} | {:error, term()} | :error
  def fetch(attrs) when is_list(attrs), do: attrs |> Enum.into(%{}) |> fetch()

  def fetch(attrs) when is_map(attrs) do
    case value(attrs, :governed_authority) do
      nil -> :error
      authority -> new(authority)
    end
  end

  def fetch(_attrs), do: :error

  @spec reject_unmanaged_attach_attrs(map()) ::
          :ok | {:error, {:unmanaged_governed_attach_field, atom()}}
  def reject_unmanaged_attach_attrs(attrs) when is_map(attrs) do
    case Enum.find(@unmanaged_attach_fields, &present?(attrs, &1)) do
      nil -> :ok
      field -> {:error, {:unmanaged_governed_attach_field, field}}
    end
  end

  @spec reject_unmanaged_target_preference(map()) ::
          :ok | {:error, {:unmanaged_governed_target_preference_field, atom()}}
  def reject_unmanaged_target_preference(attrs) when is_map(attrs) do
    case Enum.find(@unmanaged_target_preference_fields, &present?(attrs, &1)) do
      nil -> :ok
      field -> {:error, {:unmanaged_governed_target_preference_field, field}}
    end
  end

  def materialize_attach_attrs(%__MODULE__{} = authority, attrs) when is_map(attrs) do
    attrs
    |> drop_fields(@unmanaged_attach_fields)
    |> Map.delete(:governed_authority)
    |> Map.delete("governed_authority")
    |> Map.merge(attach_attrs(authority))
  end

  def materialize_target_preference(%__MODULE__{} = authority, attrs) when is_map(attrs) do
    attrs
    |> drop_fields(@unmanaged_target_preference_fields)
    |> Map.delete(:governed_authority)
    |> Map.delete("governed_authority")
    |> Map.merge(%{
      backend: authority.backend,
      startup_kind: authority.startup_kind,
      execution_surface: execution_surface(authority),
      backend_options: attach_attrs(authority),
      metadata: metadata(authority)
    })
  end

  @spec refs(t()) :: map()
  def refs(%__MODULE__{} = authority) do
    %{
      endpoint_ref: authority.endpoint_ref,
      service_identity_ref: authority.service_identity_ref,
      provider_account_ref: authority.provider_account_ref,
      model_account_ref: authority.model_account_ref,
      target_ref: authority.target_ref,
      target_posture_ref: authority.target_posture_ref,
      attach_grant_ref: authority.attach_grant_ref,
      credential_ref: authority.credential_ref,
      credential_lease_ref: authority.credential_lease_ref,
      operation_policy_ref: authority.operation_policy_ref,
      redaction_ref: authority.redaction_ref
    }
  end

  defp attach_attrs(%__MODULE__{} = authority) do
    authority.backend_options
    |> Map.new()
    |> Map.merge(%{
      root_url: authority.root_url,
      model_identity: authority.model_identity,
      api_key: authority.api_key,
      headers: headers(authority),
      ollama_http: authority.ollama_http,
      ready_timeout_ms: authority.ready_timeout_ms,
      readiness_interval_ms: authority.readiness_interval_ms,
      health_interval_ms: authority.health_interval_ms,
      execution_surface: execution_surface(authority),
      metadata: metadata(authority)
    })
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp headers(%__MODULE__{} = authority) do
    authority.headers
    |> normalize_headers()
    |> maybe_put_authorization(authority.api_key)
  end

  defp metadata(%__MODULE__{} = authority) do
    authority.metadata
    |> Map.new()
    |> Map.put(:governed_authority_refs, refs(authority))
  end

  defp execution_surface(%__MODULE__{execution_surface: nil} = authority) do
    [
      surface_kind: :local_subprocess,
      target_id: authority.target_ref,
      lease_ref: authority.attach_grant_ref,
      surface_ref: authority.endpoint_ref,
      boundary_class: :self_hosted_inference
    ]
  end

  defp execution_surface(%__MODULE__{execution_surface: surface}), do: surface

  defp validate(%__MODULE__{} = authority) do
    with :ok <- validate_backend(authority.backend),
         :ok <- validate_startup_kind(authority.startup_kind),
         :ok <- validate_refs(authority, @required_refs, :required),
         :ok <- validate_refs(authority, @optional_refs, :optional),
         :ok <- validate_non_empty(:root_url, authority.root_url),
         :ok <- validate_non_empty(:model_identity, authority.model_identity),
         :ok <- validate_optional_binary(:api_key, authority.api_key),
         :ok <- validate_headers(authority.headers),
         :ok <- validate_http(authority.ollama_http),
         :ok <- validate_distinct_identity_refs(authority),
         :ok <- validate_positive_integer(:ready_timeout_ms, authority.ready_timeout_ms),
         :ok <- validate_positive_integer(:readiness_interval_ms, authority.readiness_interval_ms),
         :ok <- validate_positive_integer(:health_interval_ms, authority.health_interval_ms),
         :ok <- validate_map(:backend_options, authority.backend_options),
         :ok <- validate_map(:metadata, authority.metadata) do
      {:ok, %{authority | headers: normalize_headers(authority.headers)}}
    end
  end

  defp validate_backend(backend) when is_atom(backend), do: :ok

  defp validate_backend(backend) when is_binary(backend),
    do: validate_non_empty(:backend, backend)

  defp validate_backend(backend), do: {:error, {:backend, backend}}

  defp validate_startup_kind(nil), do: :ok
  defp validate_startup_kind(:spawned), do: :ok
  defp validate_startup_kind(:attach_existing_service), do: :ok
  defp validate_startup_kind("spawned"), do: :ok
  defp validate_startup_kind("attach_existing_service"), do: :ok
  defp validate_startup_kind(startup_kind), do: {:error, {:startup_kind, startup_kind}}

  defp validate_refs(authority, refs, mode) do
    Enum.reduce_while(refs, :ok, fn field, :ok ->
      value = Map.fetch!(authority, field)

      case {mode, value} do
        {:optional, nil} -> {:cont, :ok}
        _other -> reduce_validation(validate_non_empty(field, value))
      end
    end)
  end

  defp reduce_validation(:ok), do: {:cont, :ok}
  defp reduce_validation({:error, _reason} = error), do: {:halt, error}

  defp validate_non_empty(field, value) when is_binary(value) do
    if String.trim(value) == "" do
      {:error, {:missing_governed_authority_field, field}}
    else
      :ok
    end
  end

  defp validate_non_empty(field, _value), do: {:error, {:missing_governed_authority_field, field}}

  defp validate_optional_binary(_field, nil), do: :ok
  defp validate_optional_binary(field, value), do: validate_non_empty(field, value)

  defp validate_headers(headers) when is_map(headers), do: :ok
  defp validate_headers(headers), do: {:error, {:headers, headers}}

  defp validate_http(nil), do: :ok
  defp validate_http(http) when is_function(http, 4), do: :ok
  defp validate_http(http), do: {:error, {:ollama_http, http}}

  defp validate_distinct_identity_refs(%__MODULE__{} = authority) do
    cond do
      authority.service_identity_ref == authority.provider_account_ref ->
        {:error, {:identity_ref_collision, :service_identity_ref, :provider_account_ref}}

      authority.endpoint_ref == authority.provider_account_ref ->
        {:error, {:identity_ref_collision, :endpoint_ref, :provider_account_ref}}

      authority.model_account_ref == authority.provider_account_ref ->
        {:error, {:identity_ref_collision, :model_account_ref, :provider_account_ref}}

      true ->
        :ok
    end
  end

  defp validate_positive_integer(_field, value) when is_integer(value) and value > 0, do: :ok
  defp validate_positive_integer(field, value), do: {:error, {field, value}}

  defp validate_map(_field, map) when is_map(map), do: :ok
  defp validate_map(field, value), do: {:error, {field, value}}

  defp normalize_headers(headers) when is_map(headers) do
    Enum.into(headers, %{}, fn {key, value} ->
      {String.downcase(to_string(key)), to_string(value)}
    end)
  end

  defp maybe_put_authorization(headers, nil), do: headers

  defp maybe_put_authorization(headers, api_key) do
    Map.put(headers, "authorization", "Bearer " <> String.trim(to_string(api_key)))
  end

  defp drop_fields(attrs, fields) do
    Enum.reduce(fields, attrs, fn field, acc ->
      acc
      |> Map.delete(field)
      |> Map.delete(Atom.to_string(field))
    end)
  end

  defp present?(attrs, field) do
    Map.has_key?(attrs, field) or Map.has_key?(attrs, Atom.to_string(field))
  end

  defp value(attrs, key, default \\ nil) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key), default))
  end
end
