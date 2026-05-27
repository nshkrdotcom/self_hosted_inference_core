defmodule SelfHostedInferenceCore.Readiness do
  @moduledoc """
  Readiness helper for configured service and Crucible runtimes.
  """

  alias SelfHostedInferenceCore.CrucibleRuntime

  @spec ready?() :: boolean()
  def ready? do
    case CrucibleRuntime.list_snapshots() do
      [] -> true
      snapshots -> Enum.any?(snapshots, & &1.ready?)
    end
  end
end
