defmodule SelfHostedInferenceCore.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      SelfHostedInferenceCore.BackendRegistry,
      {Registry, keys: :unique, name: SelfHostedInferenceCore.ProcessRegistry},
      {DynamicSupervisor,
       strategy: :one_for_one, name: SelfHostedInferenceCore.RuntimeSupervisor},
      {DynamicSupervisor,
       strategy: :one_for_one, name: SelfHostedInferenceCore.CrucibleRuntimeSupervisor}
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: SelfHostedInferenceCore.Supervisor
    )
  end
end
