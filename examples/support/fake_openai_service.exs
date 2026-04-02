defmodule SelfHostedInferenceCore.Examples.FakeOpenAIService do
  @moduledoc false

  def main do
    [state_dir] = System.argv()
    File.mkdir_p!(state_dir)
    File.write!(Path.join(state_dir, "status.txt"), "healthy")
    IO.puts("READY #{state_dir}")
    sleep_forever()
  end

  defp sleep_forever do
    receive do
    after
      1_000 -> sleep_forever()
    end
  end
end

SelfHostedInferenceCore.Examples.FakeOpenAIService.main()
