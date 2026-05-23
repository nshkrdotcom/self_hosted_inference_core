defmodule SelfHostedInferenceCore.RouteLogits do
  @moduledoc """
  Generic route-head output returned by adapter backends.
  """

  @enforce_keys [
    :role_logits,
    :agent_logits,
    :selected_role_id,
    :selected_agent_id,
    :token_count,
    :transcript_hash,
    :route_hash_inputs,
    :backend_label,
    :runtime_profile,
    :margins
  ]
  defstruct [
    :role_logits,
    :agent_logits,
    :selected_role_id,
    :selected_agent_id,
    :token_count,
    :transcript_hash,
    :route_hash_inputs,
    :backend_label,
    :runtime_profile,
    :margins
  ]

  @type t :: %__MODULE__{
          role_logits: term(),
          agent_logits: term(),
          selected_role_id: term(),
          selected_agent_id: term(),
          token_count: non_neg_integer(),
          transcript_hash: String.t(),
          route_hash_inputs: map(),
          backend_label: term(),
          runtime_profile: term(),
          margins: map()
        }
end
