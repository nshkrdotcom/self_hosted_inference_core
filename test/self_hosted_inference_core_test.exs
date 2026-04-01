defmodule SelfHostedInferenceCoreTest do
  use ExUnit.Case
  doctest SelfHostedInferenceCore

  test "greets the world" do
    assert SelfHostedInferenceCore.hello() == :world
  end
end
