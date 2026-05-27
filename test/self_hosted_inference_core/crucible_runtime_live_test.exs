defmodule SelfHostedInferenceCore.CrucibleRuntimeLiveTest do
  use ExUnit.Case, async: false

  @moduletag :live_cpu_heavy

  test "live crucible runtime is opt-in" do
    assert System.get_env("CRUCIBLE_LIVE_MODEL") in ["1", "true"]
  end
end
