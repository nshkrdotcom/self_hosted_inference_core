defmodule SelfHostedInferenceCore.FixtureProviderTapTest do
  use ExUnit.Case, async: true

  alias Crucible.CapabilityReport
  alias CrucibleTap.TapPlan
  alias SelfHostedInferenceCore.CrucibleRuntime.FixtureProvider

  setup do
    assert {:ok, state} = FixtureProvider.init(model_id: "model:fixture")
    {:ok, state: state}
  end

  test "surface declares only final_logits for fixture provider", %{state: state} do
    assert {:ok, surface} = FixtureProvider.surface(state, [])
    assert surface.adapter == :fixture
    assert surface.model_family == :example_transformer
    assert length(surface.nodes) == 1
    assert hd(surface.nodes).signal_type == :final_logits
  end

  test "compile_tap_plan succeeds for supported final_logits tap", %{state: state} do
    plan =
      TapPlan.new!(
        [
          [
            id: "logits",
            signal_type: :final_logits,
            layers: [:final],
            selector: %{layer_name: "lm_head.output"}
          ]
        ],
        plan_id: "fixture-final-logits"
      )

    assert {:ok, compiled, %CapabilityReport{} = report} =
             FixtureProvider.compile_tap_plan(state, plan, [])

    assert compiled.plan_id == "fixture-final-logits"
    assert [%{tap_id: "logits"}] = compiled.matched
    assert report.provider_kind == :fixture
    assert report.model_id == "model:fixture"
    assert report.required_missing == []
  end

  test "compile_tap_plan fails closed when required tap is unsupported", %{state: state} do
    plan =
      TapPlan.new!(
        [[id: "hidden", signal_type: :middle_residuals, layers: [0], required?: true]],
        plan_id: "fixture-required-hidden"
      )

    assert {:error, {:tap_compile_failed, %CapabilityReport{} = report}} =
             FixtureProvider.compile_tap_plan(state, plan, [])

    assert [%{capability: "hidden"}] = report.failed
    assert "hidden" in report.required_missing
  end

  test "compile_tap_plan degrades optional unsupported taps", %{state: state} do
    plan =
      TapPlan.new!(
        [[id: "hidden", signal_type: :middle_residuals, layers: [0], required?: false]],
        plan_id: "fixture-optional-hidden"
      )

    assert {:ok, compiled, %CapabilityReport{} = report} =
             FixtureProvider.compile_tap_plan(state, plan, [])

    assert compiled.plan_id == "fixture-optional-hidden"
    assert report.optional_dropped == ["hidden"]
    assert report.failed == []
  end
end
