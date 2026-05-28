defmodule SelfHostedInferenceCore.CrucibleRuntime.Worker do
  @moduledoc false

  use GenServer

  alias CrucibleBumblebee.{
    ExampleSurface,
    ForwardRunner,
    GenerationRunner,
    Live,
    ManualGeneration,
    ModelLoader,
    ModelLoader.Options,
    ModelSurface,
    Preflight,
    TraceWriter
  }

  alias CrucibleTap.TapPlan
  alias SelfHostedInferenceCore.{CrucibleArtifacts, CrucibleRuntime, LeaseRef}

  @default_tap_plan_id "crucible-runtime-default"

  def child_spec(opts) when is_map(opts), do: child_spec(Map.to_list(opts))

  def child_spec(opts) when is_list(opts) do
    id = Keyword.fetch!(opts, :id)

    %{
      id: {__MODULE__, id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent
    }
  end

  def start_link(opts) when is_map(opts), do: start_link(Map.to_list(opts))

  def start_link(opts) when is_list(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: CrucibleRuntime.via(id))
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    if Keyword.get(opts, :live_model?, false) do
      init_live(opts)
    else
      init_fixture(opts)
    end
  end

  defp init_fixture(opts) do
    with {:ok, surface} <- resolve_surface(opts),
         {:ok, tap_plan} <- resolve_tap_plan(opts),
         {:ok, forward_serving} <- compile_forward_serving(opts, surface, tap_plan) do
      state = %{
        provider: :fixture,
        id: Keyword.fetch!(opts, :id),
        model_ref: Keyword.get(opts, :model_ref, "model:fixture"),
        backend: Keyword.get(opts, :backend_preference, :auto),
        surface: surface,
        tap_plan: tap_plan,
        forward_serving: forward_serving,
        generation_runner: Keyword.get(opts, :generation_runner),
        model_bundle: nil,
        capability_report: nil,
        ready?: true,
        tokenizer_loaded?: true,
        model_loaded?: true,
        last_forward_ok?: false,
        last_error: nil,
        state_machine: [
          :init,
          :select_backend,
          :load_tokenizer,
          :load_model,
          :preflight_surface,
          :compile_tap_plan,
          :ready
        ],
        leases: %{},
        lease_timers: %{},
        started_at_ms: now_ms()
      }

      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  defp init_live(opts) do
    loader_options = live_loader_options(opts)

    case ModelLoader.load(loader_options) do
      {:ok, bundle} ->
        tap_plan = Live.forward_tap_plan()
        preflight = Preflight.run!(bundle, tap_plan)

        state = %{
          provider: :elixir_bumblebee,
          id: Keyword.fetch!(opts, :id),
          model_ref: bundle.model_id,
          backend: bundle.backend,
          surface: preflight.surface,
          tap_plan: tap_plan,
          forward_serving: nil,
          generation_runner: nil,
          model_bundle: bundle,
          loader_options: loader_options,
          capability_report: preflight.capability_report,
          ready?: true,
          tokenizer_loaded?: true,
          model_loaded?: true,
          last_forward_ok?: false,
          last_error: nil,
          state_machine: [
            :init,
            :select_backend,
            :load_tokenizer,
            :load_model,
            :preflight_surface,
            :compile_tap_plan,
            :ready
          ],
          leases: %{},
          lease_timers: %{},
          started_at_ms: now_ms()
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  rescue
    error -> {:stop, {:live_model_start_failed, Exception.message(error)}}
  end

  @impl true
  def handle_call(:capabilities, _from, state) do
    {:reply, {:ok, capabilities(state)}, state}
  end

  def handle_call(:ready?, _from, state) do
    {:reply, state.ready?, state}
  end

  def handle_call({:lease, opts}, _from, %{ready?: true} = state) do
    lease_ref =
      "crucible-lease-" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))

    ttl_ms = Keyword.get(opts, :ttl_ms)

    lease =
      LeaseRef.new!(
        lease_ref: lease_ref,
        owner_ref: Keyword.get(opts, :owner_ref),
        ttl_ms: ttl_ms,
        renewable?: Keyword.get(opts, :renewable?, true),
        metadata: %{
          runtime: state.id,
          runtime_pid: self(),
          backend: state.backend,
          surface: state.surface.id,
          capabilities: capabilities(state)
        }
      )

    timer =
      if is_integer(ttl_ms) and ttl_ms > 0 do
        Process.send_after(self(), {:lease_expired, lease_ref}, ttl_ms)
      end

    :telemetry.execute(
      [:self_hosted_inference_core, :lease, :acquire],
      %{count: 1},
      %{runtime_kind: :crucible, runtime: state.id, lease_ref: lease_ref}
    )

    {:reply, {:ok, lease}, put_lease(state, lease_ref, lease, timer)}
  end

  def handle_call({:lease, _opts}, _from, state), do: {:reply, {:error, :not_ready}, state}

  def handle_call({:release, lease_ref}, _from, state) do
    {:reply, :ok, release_lease(state, lease_ref)}
  end

  def handle_call(
        {:forward, _tap_plan, input, opts},
        _from,
        %{ready?: true, provider: :elixir_bumblebee} = state
      ) do
    {result, state} = run_live_forward(state, input, opts)
    {:reply, result, state}
  end

  def handle_call({:forward, _tap_plan, input, opts}, _from, %{ready?: true} = state) do
    result =
      ForwardRunner.run_serving(
        state.forward_serving,
        input,
        Keyword.merge([trace_id: trace_id(state), model_ref: state.model_ref], opts)
      )

    {:reply, result, %{state | last_forward_ok?: true, last_error: nil}}
  end

  def handle_call({:forward, _tap_plan, _input, _opts}, _from, state) do
    {:reply, {:error, :not_ready}, state}
  end

  def handle_call(
        {:generate, _tap_plan, input, opts},
        _from,
        %{ready?: true, provider: :elixir_bumblebee} = state
      ) do
    {result, state} = run_live_generation(state, input, opts)
    {:reply, result, state}
  end

  def handle_call({:generate, _tap_plan, input, opts}, _from, %{ready?: true} = state) do
    steering_plan = Keyword.get(opts, :steering_plan)

    result =
      case state.generation_runner do
        nil ->
          {:error, :generation_unavailable}

        runner ->
          GenerationRunner.generate(
            runner,
            input,
            steering_plan,
            state.surface,
            Keyword.put(
              opts,
              :custom_loop,
              Keyword.get(opts, :custom_loop, is_function(runner, 2))
            )
          )
      end

    {:reply, result, state}
  end

  def handle_call({:generate, _tap_plan, _input, _opts}, _from, state) do
    {:reply, {:error, :not_ready}, state}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, snapshot(state), state}
  end

  @impl true
  def handle_info({:lease_expired, lease_ref}, state) do
    {:noreply, release_lease(state, lease_ref)}
  end

  def handle_info({:EXIT, _pid, _reason}, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.lease_timers, fn {_lease_ref, timer} -> cancel_timer(timer) end)
    :ok
  end

  defp resolve_surface(opts) do
    surface_module = Keyword.get(opts, :surface_module, ExampleSurface)
    surface_opts = Keyword.get(opts, :surface_opts, num_blocks: 1)

    {:ok, surface_module.surface(surface_opts)}
  rescue
    error -> {:error, {:surface_start_failed, Exception.message(error)}}
  end

  defp resolve_tap_plan(opts) do
    case Keyword.get(opts, :serving_tap_plan) do
      %TapPlan{} = tap_plan ->
        {:ok, tap_plan}

      nil ->
        {:ok,
         TapPlan.new!(
           [
             [id: "hidden", signal_type: :middle_residuals, layers: [0]],
             [id: "logits", signal_type: :final_logits, layers: [:final]]
           ],
           plan_id: @default_tap_plan_id
         )}

      other ->
        {:error, {:invalid_serving_tap_plan, other}}
    end
  end

  defp compile_forward_serving(opts, %ModelSurface{} = surface, %TapPlan{} = tap_plan) do
    predict_fun = Keyword.get(opts, :predict_fun, &default_predict_fun/1)

    ForwardRunner.compile_serving(predict_fun, tap_plan,
      model_ref: Keyword.get(opts, :model_ref, "model:fixture"),
      surface: surface,
      serving_ref: "crucible-serving:#{Keyword.fetch!(opts, :id)}"
    )
  end

  defp default_predict_fun(_input) do
    %{
      logits: Nx.tensor([[0.1, 0.4, 0.2]], type: :f32),
      hidden_states: {
        Nx.tensor([[1.0, 0.0]], type: :f32),
        Nx.tensor([[0.0, 1.0]], type: :f32),
        Nx.tensor([[1.0, 1.0]], type: :f32)
      },
      cache: %{blocks: {:block0}}
    }
  end

  defp put_lease(state, lease_ref, lease, timer) do
    state
    |> put_in([:leases, lease_ref], lease)
    |> put_in([:lease_timers, lease_ref], timer)
  end

  defp release_lease(state, lease_ref) do
    cancel_timer(Map.get(state.lease_timers, lease_ref))

    if Map.has_key?(state.leases, lease_ref) do
      :telemetry.execute(
        [:self_hosted_inference_core, :lease, :release],
        %{count: 1},
        %{runtime_kind: :crucible, runtime: state.id, lease_ref: lease_ref}
      )
    end

    state
    |> update_in([:leases], &Map.delete(&1, lease_ref))
    |> update_in([:lease_timers], &Map.delete(&1, lease_ref))
  end

  defp snapshot(state) do
    %{
      id: state.id,
      ready?: state.ready?,
      runtime_id: to_string(state.id),
      provider_kind:
        if(state.provider == :elixir_bumblebee, do: :elixir_bumblebee, else: :fixture),
      model_id: state.model_ref,
      tokenizer_loaded?: state.tokenizer_loaded?,
      model_loaded?: state.model_loaded?,
      backend: state.backend,
      surface: state.surface.id,
      model_ref: state.model_ref,
      lease_count: map_size(state.leases),
      active_leases: map_size(state.leases),
      capabilities: capabilities(state),
      last_forward_ok?: state.last_forward_ok?,
      last_error: state.last_error,
      state_machine: state.state_machine,
      started_at_ms: state.started_at_ms
    }
  end

  defp capabilities(%{capability_report: %Crucible.CapabilityReport{} = report}), do: report

  defp capabilities(state) do
    state.surface.capabilities
    |> Map.put(:backend, state.backend)
    |> Map.put(:surface, state.surface.id)
  end

  defp run_live_forward(state, input, opts) do
    prompt = prompt_from_input(input)
    name = Keyword.get(opts, :trace_name, "hosted_runtime_#{state.id}")
    trace_id = "tr_#{System.unique_integer([:positive])}"
    run_id = "run_#{System.unique_integer([:positive])}"
    root = state.loader_options.artifact_root
    trace_path = CrucibleArtifacts.trace_path(name, root: root)
    report_path = CrucibleArtifacts.capability_report_path(name, root: root)
    started = System.monotonic_time(:millisecond)
    forward_started = System.monotonic_time(:millisecond)

    TraceWriter.reset!(trace_path)
    TraceWriter.write_capability_report!(report_path, capabilities(state))

    TraceWriter.write!(trace_path, :trace_start,
      trace_id: trace_id,
      run_id: run_id,
      provider_kind: :elixir_bumblebee,
      model_id: state.model_bundle.model_id,
      model_family: state.model_bundle.model_family,
      backend: state.model_bundle.backend,
      hosted_runtime_id: to_string(state.id)
    )

    TraceWriter.write!(trace_path, :provider_capability_report,
      trace_id: trace_id,
      capability_report: capabilities(state),
      capability_report_digest: Crucible.CanonicalJSON.digest(capabilities(state))
    )

    TraceWriter.write!(trace_path, :forward_start,
      trace_id: trace_id,
      prompt_digest: CrucibleSignalTrace.Digest.prefixed_text(prompt)
    )

    logits = Live.run_logits(state.model_bundle, prompt)

    signal =
      TraceWriter.signal_from_logits(logits, %{
        signal_id: "sig_final_logits",
        trace_id: trace_id,
        run_id: run_id,
        model_id: state.model_bundle.model_id,
        model_family: state.model_bundle.model_family,
        model_revision: state.model_bundle.revision,
        backend: state.model_bundle.backend,
        capture_method: :hosted_loaded_bundle
      })

    TraceWriter.write!(trace_path, :signal_record, trace_id: trace_id, signal: signal)

    TraceWriter.write!(trace_path, :forward_end,
      trace_id: trace_id,
      forward_time_ms: elapsed_ms(forward_started)
    )

    TraceWriter.write!(trace_path, :trace_end,
      trace_id: trace_id,
      status: :ok,
      duration_ms: elapsed_ms(started)
    )

    trace = CrucibleSignalTrace.Ingest.from_jsonl!(trace_path, [])

    {{:ok, trace}, %{state | last_forward_ok?: true, last_error: nil}}
  rescue
    error ->
      reason = Exception.message(error)
      {{:error, reason}, %{state | last_forward_ok?: false, last_error: reason}}
  end

  defp run_live_generation(%{model_bundle: %{model_family: family}} = state, input, opts)
       when family in [:gpt2, :qwen3] do
    prompt = prompt_from_input(input)

    case ManualGeneration.run(state.model_bundle, prompt,
           max_new_tokens:
             Keyword.get(opts, :max_new_tokens, state.loader_options.max_new_tokens || 1),
           strategy: Keyword.get(opts, :generation_strategy, :greedy),
           seed: Keyword.get(opts, :seed, state.loader_options.seed),
           stop_token_ids: Keyword.get(opts, :stop_token_ids, [])
         ) do
      {:ok, generation} ->
        result = %{
          model_id: state.model_bundle.model_id,
          backend: state.model_bundle.backend,
          generated_token_ids: generation.generated_token_ids,
          decoded_text: generation.decoded_text,
          step_count: length(generation.steps),
          success_level: :generation_step_logits
        }

        {{:ok, result}, %{state | last_error: nil}}

      {:error, reason} ->
        {{:error, reason}, %{state | last_error: reason}}
    end
  end

  defp run_live_generation(state, _input, _opts) do
    reason = {:generation_unavailable_for_model_family, state.model_bundle.model_family}
    {{:error, reason}, %{state | last_error: reason}}
  end

  defp prompt_from_input(%{prompt: prompt}) when is_binary(prompt), do: prompt
  defp prompt_from_input(%{"prompt" => prompt}) when is_binary(prompt), do: prompt
  defp prompt_from_input(prompt) when is_binary(prompt), do: prompt
  defp prompt_from_input(_input), do: "Hi"

  defp trace_id(state), do: "crucible-runtime:#{state.id}:#{System.unique_integer([:positive])}"

  defp live_loader_options(opts) do
    opts
    |> Keyword.take([
      :model_id,
      :tokenizer_id,
      :revision,
      :backend,
      :offline?,
      :cache_dir,
      :prompt,
      :max_new_tokens,
      :seed,
      :artifact_root,
      :architecture,
      :module,
      :diagnostic_path
    ])
    |> Options.from_env()
  end

  defp elapsed_ms(start_ms), do: System.monotonic_time(:millisecond) - start_ms

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)

  defp now_ms, do: System.system_time(:millisecond)
end
