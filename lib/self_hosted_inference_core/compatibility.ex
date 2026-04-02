defmodule SelfHostedInferenceCore.Compatibility do
  @moduledoc false

  alias SelfHostedInferenceCore.{BackendManifest, CompatibilityResult, ConsumerManifest}

  @spec resolve(BackendManifest.t(), ConsumerManifest.t()) :: CompatibilityResult.t()
  def resolve(%BackendManifest{} = backend_manifest, %ConsumerManifest{} = consumer_manifest) do
    runtime_kind = backend_manifest.runtime_kind

    management_mode =
      first_match(backend_manifest.management_modes, consumer_manifest.accepted_management_modes)

    protocol = first_match(backend_manifest.protocols, consumer_manifest.accepted_protocols)

    cond do
      runtime_kind not in consumer_manifest.accepted_runtime_kinds ->
        incompatible(:runtime_kind_mismatch, [:runtime_kind])

      is_nil(management_mode) ->
        incompatible(:management_mode_mismatch, [:management_mode])

      is_nil(protocol) ->
        incompatible(:unsupported_protocol, [:protocol])

      startup_kind_mismatch?(backend_manifest, consumer_manifest) ->
        incompatible(:startup_kind_unsupported, [:startup_kind])

      capability_failure = required_capability_failure(backend_manifest, consumer_manifest) ->
        capability_failure

      true ->
        CompatibilityResult.new!(
          compatible?: true,
          reason: :protocol_match,
          resolved_runtime_kind: runtime_kind,
          resolved_management_mode: management_mode,
          resolved_protocol: protocol,
          warnings: capability_warnings(backend_manifest, consumer_manifest),
          metadata: %{
            backend: backend_manifest.backend,
            consumer: consumer_manifest.consumer
          }
        )
    end
  end

  defp startup_kind_mismatch?(%BackendManifest{startup_kind: startup_kind}, %ConsumerManifest{
         constraints: constraints
       }) do
    case Map.get(constraints, :startup_kind, Map.get(constraints, "startup_kind")) do
      nil -> false
      expected -> expected != startup_kind
    end
  end

  defp required_capability_failure(
         %BackendManifest{} = backend_manifest,
         %ConsumerManifest{} = consumer_manifest
       ) do
    Enum.find_value(consumer_manifest.required_capabilities, fn {key, expected} ->
      actual = capability_value(backend_manifest.capabilities, key)

      cond do
        capability_satisfied?(actual, expected) ->
          nil

        key == :streaming? ->
          incompatible(:missing_streaming, [:streaming])

        true ->
          incompatible(:missing_capability, [normalize_requirement_key(key)])
      end
    end)
  end

  defp capability_warnings(
         %BackendManifest{} = backend_manifest,
         %ConsumerManifest{} = consumer_manifest
       ) do
    Enum.reduce(consumer_manifest.optional_capabilities, [], fn {key, expected}, warnings ->
      actual = capability_value(backend_manifest.capabilities, key)

      if capability_satisfied?(actual, expected) do
        warnings
      else
        [normalize_requirement_key(key) | warnings]
      end
    end)
    |> Enum.reverse()
  end

  defp capability_satisfied?(actual, expected) when expected in [true, false],
    do: actual == expected

  defp capability_satisfied?(actual, :unknown), do: actual == :unknown
  defp capability_satisfied?(actual, expected), do: actual == expected

  defp normalize_requirement_key(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> String.trim_trailing("?")
    |> String.to_atom()
  end

  defp normalize_requirement_key(_key), do: :capability

  defp capability_value(capabilities, key) when is_atom(key) do
    Map.get(capabilities, key, Map.get(capabilities, Atom.to_string(key)))
  end

  defp capability_value(capabilities, key) when is_binary(key) do
    Map.get(capabilities, key)
  end

  defp capability_value(_capabilities, _key), do: nil

  defp incompatible(reason, missing_requirements) do
    CompatibilityResult.new!(
      compatible?: false,
      reason: reason,
      missing_requirements: missing_requirements
    )
  end

  defp first_match(left, right) do
    Enum.find(left, &(&1 in right))
  end
end
