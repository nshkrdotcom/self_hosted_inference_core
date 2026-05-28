defmodule SelfHostedInferenceCore.TestSupport.FailingCrucibleProvider do
  @moduledoc false

  @behaviour SelfHostedInferenceCore.CrucibleRuntime.Provider

  @impl true
  def init(opts), do: {:error, Keyword.get(opts, :reason, :preflight_failed)}

  @impl true
  def forward(_state, _input, _opts), do: {:error, :not_started}

  @impl true
  def generate(_state, _input, _opts), do: {:error, :not_started}

  @impl true
  def capabilities(_state), do: %{}

  @impl true
  def provider_kind(_state), do: :failing_fixture

  @impl true
  def model_id(_state), do: "model:failing"

  @impl true
  def backend(_state), do: :fixture

  @impl true
  def surface_id(_state), do: :failing_fixture

  @impl true
  def ready?(_state), do: false

  @impl true
  def tokenizer_loaded?(_state), do: false

  @impl true
  def model_loaded?(_state), do: false

  @impl true
  def state_machine(_state), do: [:init, :blocked]
end
