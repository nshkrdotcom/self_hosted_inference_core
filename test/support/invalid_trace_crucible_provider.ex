defmodule SelfHostedInferenceCore.TestSupport.InvalidTraceCrucibleProvider do
  @moduledoc false

  @behaviour SelfHostedInferenceCore.CrucibleRuntime.Provider

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def forward(_state, _input, _opts) do
    {:ok,
     %Crucible.ForwardTrace{
       trace_id: "invalid-trace",
       provider_kind: :invalid_fixture,
       model_id: "model:invalid",
       signals: []
     }}
  end

  @impl true
  def generate(_state, _input, _opts), do: {:error, :not_implemented}

  @impl true
  def capabilities(_state), do: %{}

  @impl true
  def provider_kind(_state), do: :invalid_fixture

  @impl true
  def model_id(_state), do: "model:invalid"

  @impl true
  def backend(_state), do: :fixture

  @impl true
  def surface_id(_state), do: :invalid_fixture

  @impl true
  def ready?(_state), do: true

  @impl true
  def tokenizer_loaded?(_state), do: false

  @impl true
  def model_loaded?(_state), do: false

  @impl true
  def state_machine(_state), do: [:ready]
end
