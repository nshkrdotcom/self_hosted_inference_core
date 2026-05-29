defmodule SelfHostedInferenceCore.CrucibleRuntime.Provider do
  @moduledoc """
  Provider contract for Crucible runtime model execution.

  The core runtime owns supervision, readiness, leases, health snapshots, and
  provider lifecycle. Concrete model adapters own model loading, forward
  execution, generation, signal extraction, and artifact writing.
  """

  @type state :: term()

  @callback init(keyword()) :: {:ok, state()} | {:error, term()}
  @callback forward(state(), input :: term(), opts :: keyword()) ::
              {:ok, Crucible.ForwardTrace.t()} | {:error, term()}
  @callback generate(state(), input :: term(), opts :: keyword()) ::
              {:ok, term()} | {:error, term()}
  @callback capabilities(state()) :: map() | Crucible.CapabilityReport.t()
  @callback provider_kind(state()) :: atom()
  @callback model_id(state()) :: String.t()
  @callback backend(state()) :: atom() | term()
  @callback surface_id(state()) :: atom() | String.t() | nil
  @callback ready?(state()) :: boolean()
  @callback tokenizer_loaded?(state()) :: boolean()
  @callback model_loaded?(state()) :: boolean()
  @callback state_machine(state()) :: [atom()]

  @callback surface(state(), keyword()) ::
              {:ok, CrucibleTap.Surface.t()} | {:error, term()}

  @callback compile_tap_plan(state(), CrucibleTap.TapPlan.t(), keyword()) ::
              {:ok, CrucibleTap.CompiledPlan.t(), Crucible.CapabilityReport.t()}
              | {:error, {:tap_compile_failed, Crucible.CapabilityReport.t()}}
              | {:error, term()}

  @optional_callbacks surface: 2, compile_tap_plan: 3
end
