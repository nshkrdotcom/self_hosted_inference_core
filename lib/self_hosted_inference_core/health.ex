defmodule SelfHostedInferenceCore.Health do
  @moduledoc """
  Health report for legacy and Crucible runtimes.
  """

  alias SelfHostedInferenceCore.{CrucibleRuntime, RuntimeRegistry}

  def report do
    %{
      instances: RuntimeRegistry.list_instances(),
      crucible_runtimes: CrucibleRuntime.list_snapshots()
    }
  end
end
