defmodule SelfHostedInferenceCore.CrucibleArtifactsTest do
  use ExUnit.Case, async: false

  alias SelfHostedInferenceCore.CrucibleArtifacts

  setup do
    previous_root = System.get_env("CRUCIBLE_V5_ARTIFACT_ROOT")

    root =
      Path.join(
        System.tmp_dir!(),
        "self_hosted_crucible_artifacts_#{System.unique_integer([:positive])}"
      )

    System.put_env("CRUCIBLE_V5_ARTIFACT_ROOT", root)

    on_exit(fn ->
      restore_env("CRUCIBLE_V5_ARTIFACT_ROOT", previous_root)
      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  test "shares the V5 artifact layout with Crucible Bumblebee", %{root: root} do
    assert CrucibleArtifacts.ensure_layout!() == root
    assert File.dir?(Path.join(root, "traces/native"))
    assert File.dir?(Path.join(root, "capability_reports"))
  end

  test "names hosted traces separately from standalone traces", %{root: root} do
    assert CrucibleArtifacts.trace_path("gpt2 binary") ==
             Path.join([root, "traces/native", "hosted_gpt2_binary.trace.jsonl"])
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
