defmodule SelfHostedInferenceCore.Examples.CrucibleRuntimeLadderLive do
  @moduledoc false

  alias SelfHostedInferenceCore.CrucibleRuntime

  @default_models ["hf-internal-testing/tiny-random-gpt2"]

  def main(argv) do
    argv = normalize_argv(argv)
    gate? = "--gate" in argv

    {opts, _rest, _invalid} =
      OptionParser.parse(argv,
        strict: [
          backend: :string,
          models: :string,
          provider_module: :string,
          artifact_root: :string,
          forward_timeout_ms: :integer,
          generation_timeout_ms: :integer,
          gate: :boolean
        ]
      )

    case provider_module(opts) do
      {:ok, module} ->
        run_live(module, opts, gate?)

      {:error, reason} ->
        IO.inspect(%{ok: false, example: "crucible_runtime_ladder_live", reason: reason})
        if gate?, do: System.halt(2)
    end
  end

  defp run_live(provider_module, opts, gate?) do
    root = Keyword.get(opts, :artifact_root, "tmp/crucible_runtime_ladder")
    backend = Keyword.get(opts, :backend, "binary")
    forward_timeout_ms = Keyword.get(opts, :forward_timeout_ms, 240_000)
    generation_timeout_ms = Keyword.get(opts, :generation_timeout_ms, 240_000)
    File.mkdir_p!(Path.join(root, "model_matrix"))
    File.mkdir_p!(Path.join(root, "reports"))

    rows =
      opts
      |> models()
      |> Enum.map(fn model_id ->
        run_model(provider_module, model_id, backend, root, forward_timeout_ms, generation_timeout_ms)
      end)

    report_path = write_report!(rows, root)
    result = %{ok: Enum.all?(rows, &(&1.result == "passed")), rows: rows, report_path: report_path}
    IO.inspect(result)

    if gate? and not result.ok, do: System.halt(7)
  end

  defp provider_module(opts) do
    module_name =
      Keyword.get(
        opts,
        :provider_module,
        "SelfHostedInferenceBumblebee.CrucibleProvider"
      )

    provider =
      case module_name do
        "SelfHostedInferenceCore.CrucibleRuntime.FixtureProvider" ->
          SelfHostedInferenceCore.CrucibleRuntime.FixtureProvider

        "SelfHostedInferenceBumblebee.CrucibleProvider" ->
          SelfHostedInferenceBumblebee.CrucibleProvider

        other ->
          {:unsupported_provider_module, other}
      end

    if is_atom(provider) and Code.ensure_loaded?(provider) do
      {:ok, provider}
    else
      {:error, {:provider_not_loaded, provider}}
    end
  end

  defp models(opts) do
    opts
    |> Keyword.get(:models, Enum.join(@default_models, ","))
    |> String.split(",", trim: true)
  end

  defp run_model(provider_module, model_id, backend, root, forward_timeout_ms, generation_timeout_ms) do
    id = :"crucible-runtime-ladder-#{System.unique_integer([:positive])}"
    started = System.monotonic_time(:millisecond)

    with {:ok, pid} <- start_runtime(provider_module, model_id, id, backend, root),
         true <- CrucibleRuntime.ready?(pid),
         {:ok, lease} <- CrucibleRuntime.lease(pid, owner_ref: "hosted-ladder"),
         {:ok, trace} <- forward(pid, model_id, backend, forward_timeout_ms) do
      generation = maybe_generate(pid, generation_timeout_ms)
      :ok = CrucibleRuntime.release(lease)

      row = %{
        model_id: model_id,
        backend: backend,
        hosted_runtime: true,
        ready: true,
        lease: true,
        forward: true,
        generation: generation.ok,
        generation_result: generation.result,
        generation_step_count: generation.step_count,
        trace_id: trace.trace_id,
        signal_count: length(trace.signals),
        result: "passed",
        duration_ms: elapsed_ms(started)
      }

      write_row!(row, root)
      row
    else
      false ->
        row = failed_row(model_id, backend, :not_ready, started)
        write_row!(row, root)
        row

      {:error, reason} ->
        row = failed_row(model_id, backend, reason, started)
        write_row!(row, root)
        row
    end
  end

  defp start_runtime(provider_module, model_id, id, backend, root) do
    CrucibleRuntime.start_child(
      id: id,
      provider_module: provider_module,
      provider_opts: [
        model_id: model_id,
        tokenizer_id: model_id,
        backend: backend,
        artifact_root: root,
        max_new_tokens: 1
      ]
    )
  end

  defp forward(pid, model_id, backend, timeout_ms) do
    CrucibleRuntime.forward(pid, nil, %{prompt: "Hi"},
      trace_name: "#{safe_name(model_id)}_#{backend}",
      timeout: timeout_ms
    )
  end

  defp maybe_generate(pid, timeout_ms) do
    case CrucibleRuntime.generate(pid, nil, "Hi", max_new_tokens: 1, timeout: timeout_ms) do
      {:ok, result} ->
        %{ok: true, result: "passed", step_count: Map.get(result, :step_count, 0)}

      {:error, reason} ->
        %{ok: false, result: inspect(reason), step_count: 0}
    end
  end

  defp failed_row(model_id, backend, reason, started) do
    %{
      model_id: model_id,
      backend: backend,
      hosted_runtime: true,
      ready: false,
      lease: false,
      forward: false,
      generation: false,
      result: "failed",
      error: inspect(reason),
      duration_ms: elapsed_ms(started)
    }
  end

  defp write_row!(row, root) do
    path = Path.join([root, "model_matrix", "hosted_runtime_ladder.jsonl"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(row) <> "\n", [:append])
  end

  defp write_report!(rows, root) do
    path = Path.join([root, "reports", "hosted_runtime_matrix.md"])

    columns = [
      {:model_id, "model_id"},
      {:backend, "backend"},
      {:result, "result"},
      {:ready, "ready"},
      {:lease, "lease"},
      {:forward, "forward"},
      {:generation, "generation"},
      {:generation_result, "generation_result"},
      {:generation_step_count, "generation_step_count"},
      {:duration_ms, "duration_ms"},
      {:error, "error"},
      {:trace_id, "trace_id"},
      {:signal_count, "signal_count"}
    ]

    body =
      [
        "# Hosted Runtime Matrix\n\n",
        "| ",
        columns |> Enum.map(&elem(&1, 1)) |> Enum.join(" | "),
        " |\n| ",
        columns |> Enum.map(fn _ -> "---" end) |> Enum.join(" | "),
        " |\n",
        Enum.map(rows, fn row ->
          [
            "| ",
            columns |> Enum.map(fn {key, _label} -> cell(Map.get(row, key)) end) |> Enum.join(" | "),
            " |\n"
          ]
        end)
      ]
      |> IO.iodata_to_binary()

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, body)
    path
  end

  defp cell(nil), do: ""
  defp cell(value), do: value |> to_string() |> String.replace("|", "\\|")

  defp safe_name(name) do
    name
    |> String.downcase()
    |> String.to_charlist()
    |> Enum.map(&safe_char/1)
    |> to_string()
    |> String.trim("_")
  end

  defp safe_char(char)
       when char in ?a..?z or char in ?0..?9 or char in [?_, ?., ?-],
       do: char

  defp safe_char(_char), do: ?_

  defp normalize_argv(["--" | rest]), do: rest
  defp normalize_argv(args), do: args

  defp elapsed_ms(start_ms), do: System.monotonic_time(:millisecond) - start_ms
end

SelfHostedInferenceCore.Examples.CrucibleRuntimeLadderLive.main(System.argv())
