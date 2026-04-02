defmodule SelfHostedInferenceCore.Backend do
  @moduledoc """
  Behaviour for self-hosted runtime backends and attach adapters.
  """

  alias ExternalRuntimeTransport.Command
  alias ExternalRuntimeTransport.ProcessExit
  alias SelfHostedInferenceCore.{BackendManifest, InstanceSpec}

  @type startup_kind :: :spawned | :attach_existing_service
  @type management_mode :: :jido_managed | :externally_managed
  @type health_status :: :healthy | :degraded | :unavailable

  @type transport_event ::
          {:message, binary()}
          | {:data, binary()}
          | {:stderr, binary()}
          | {:exit, ProcessExit.t()}
          | {:error, term()}

  defmodule TransportPlan do
    @moduledoc """
    Transport-facing portion of a backend startup plan.
    """

    defstruct command: nil,
              execution_surface: nil,
              stdout_mode: :line,
              stdin_mode: :line,
              pty?: false

    @type t :: %__MODULE__{
            command: Command.t() | String.t(),
            execution_surface: keyword() | ExternalRuntimeTransport.ExecutionSurface.t() | nil,
            stdout_mode: :line | :raw,
            stdin_mode: :line | :raw,
            pty?: boolean()
          }
  end

  defmodule StartupPlan do
    @moduledoc """
    Backend-produced runtime startup plan consumed by the kernel.
    """

    alias SelfHostedInferenceCore.Backend.TransportPlan

    defstruct backend: nil,
              instance_key: nil,
              startup_kind: nil,
              management_mode: nil,
              transport: nil,
              ready_timeout_ms: 5_000,
              readiness_interval_ms: 100,
              health_interval_ms: 1_000,
              stop_when_idle?: false,
              idle_shutdown_ms: nil,
              endpoint_template: %{},
              backend_state: nil,
              metadata: %{}

    @type t :: %__MODULE__{
            backend: atom(),
            instance_key: String.t(),
            startup_kind: SelfHostedInferenceCore.Backend.startup_kind(),
            management_mode: SelfHostedInferenceCore.Backend.management_mode(),
            transport: TransportPlan.t() | nil,
            ready_timeout_ms: pos_integer(),
            readiness_interval_ms: pos_integer(),
            health_interval_ms: pos_integer() | nil,
            stop_when_idle?: boolean(),
            idle_shutdown_ms: pos_integer() | nil,
            endpoint_template: map(),
            backend_state: term(),
            metadata: map()
          }
  end

  @callback backend_id() :: atom()
  @callback manifest() :: BackendManifest.t()
  @callback startup_plan(InstanceSpec.t()) :: {:ok, StartupPlan.t()} | {:error, term()}
  @callback probe_readiness(term()) ::
              {:pending, term()} | {:ready, map(), term()} | {:error, term(), term()}
  @callback health_check(term()) ::
              {:ok, health_status(), map(), term()} | {:error, term(), term()}
  @callback handle_transport_event(transport_event(), term()) ::
              {:pending, term()} | {:ready, map(), term()} | {:stop, term(), term()}
  @callback shutdown(term(), pid() | nil) :: :ok | {:error, term()}

  @optional_callbacks handle_transport_event: 2, shutdown: 2
end
