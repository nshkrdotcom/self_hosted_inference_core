defmodule SelfHostedInferenceCore.RuntimeSnapshot do
  @moduledoc """
  Snapshot of the current runtime-instance state exposed by the registry.
  """

  alias SelfHostedInferenceCore.EndpointDescriptor

  defstruct instance_id: nil,
            backend: nil,
            startup_kind: nil,
            management_mode: nil,
            lifecycle_status: :starting,
            health_status: :unavailable,
            lease_count: 0,
            endpoint: nil,
            inserted_at_ms: nil,
            ready_at_ms: nil,
            metadata: %{}

  @type t :: %__MODULE__{
          instance_id: String.t(),
          backend: atom(),
          startup_kind: atom(),
          management_mode: atom(),
          lifecycle_status: :starting | :ready | :failed | :stopped,
          health_status: :healthy | :degraded | :unavailable,
          lease_count: non_neg_integer(),
          endpoint: EndpointDescriptor.t() | nil,
          inserted_at_ms: integer(),
          ready_at_ms: integer() | nil,
          metadata: map()
        }
end
