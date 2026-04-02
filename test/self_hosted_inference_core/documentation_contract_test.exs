defmodule SelfHostedInferenceCore.DocumentationContractTest do
  use ExUnit.Case, async: true

  test "hexdocs navigation includes every guide and examples readme" do
    mix_exs = File.read!("mix.exs")

    expected =
      ["examples/README.md" | Path.wildcard("guides/*.md")]
      |> Enum.map(&to_string/1)
      |> MapSet.new()

    missing =
      expected
      |> Enum.reject(&String.contains?(mix_exs, &1))

    assert missing == [], "missing HexDocs extras: #{inspect(missing)}"
  end

  test "package description stays scoped to the service-runtime kernel" do
    mix_exs =
      "mix.exs"
      |> File.read!()
      |> String.downcase()

    assert mix_exs =~ "service-runtime kernel"
    refute mix_exs =~ "self-hosted inference clients"
    refute mix_exs =~ "provider adapters"
    refute mix_exs =~ "transport boundaries"
  end

  test "examples cover both startup kinds" do
    examples =
      Path.wildcard("examples/*_demo.exs")
      |> Enum.map(&Path.basename/1)
      |> MapSet.new()

    expected_examples =
      MapSet.new([
        "attach_existing_service_demo.exs",
        "lease_reuse_demo.exs"
      ])

    assert MapSet.subset?(expected_examples, examples),
           "missing example demos: #{inspect(MapSet.to_list(MapSet.difference(expected_examples, examples)))}"

    readme = File.read!("examples/README.md")

    assert readme =~ "`:spawned`"
    assert readme =~ "`:attach_existing_service`"
    assert readme =~ "attach_existing_service_demo.exs"
  end
end
