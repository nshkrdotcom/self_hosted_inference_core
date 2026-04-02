defmodule SelfHostedInferenceCore.Examples.FakeOllamaService do
  @moduledoc false

  def main do
    [state_dir] = System.argv()
    File.mkdir_p!(state_dir)

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listener)
    IO.puts("READY #{port}")
    accept_loop(listener, state_dir)
  end

  defp accept_loop(listener, state_dir) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        handle_socket(socket, state_dir)
        :ok = :gen_tcp.close(socket)
        accept_loop(listener, state_dir)

      {:error, :closed} ->
        :ok
    end
  end

  defp handle_socket(socket, state_dir) do
    case recv_request(socket, "") do
      {:ok, %{method: "GET", path: "/api/version"}} ->
        version = read_value(state_dir, "version.txt", "0.0.0")
        send_json(socket, 200, ~s({"version":"#{json_escape(version)}"}))

      {:ok, %{method: "GET", path: "/api/tags"}} ->
        send_json(socket, 200, models_response(read_models(state_dir, "installed_models.txt")))

      {:ok, %{method: "GET", path: "/api/ps"}} ->
        send_json(socket, 200, models_response(read_models(state_dir, "running_models.txt")))

      {:ok, %{method: "POST", path: "/api/show", body: body}} ->
        model = extract_json_string(body, "model")
        installed_models = read_models(state_dir, "installed_models.txt")

        if model in installed_models do
          send_json(
            socket,
            200,
            ~s({"model":"#{json_escape(model)}","details":{"family":"llama"}})
          )
        else
          send_json(socket, 404, ~s({"error":"model not found"}))
        end

      {:ok, %{method: "POST", path: "/v1/chat/completions", body: body}} ->
        model = extract_json_string(body, "model")
        installed_models = read_models(state_dir, "installed_models.txt")

        if model in installed_models do
          response_text =
            read_value(
              state_dir,
              "response_text.txt",
              "Ollama attach path is alive."
            )

          send_json(socket, 200, chat_completion_response(model, response_text))
        else
          send_json(socket, 404, ~s({"error":"model not found"}))
        end

      {:ok, _request} ->
        send_json(socket, 404, ~s({"error":"not found"}))

      {:error, reason} ->
        send_json(socket, 500, ~s({"error":"#{json_escape(inspect(reason))}"}))
    end
  end

  defp recv_request(socket, buffer) do
    case :binary.match(buffer, "\r\n\r\n") do
      {headers_end, 4} ->
        headers = binary_part(buffer, 0, headers_end + 4)
        body = binary_part(buffer, headers_end + 4, byte_size(buffer) - headers_end - 4)
        content_length = content_length(headers)

        if byte_size(body) >= content_length do
          parse_request(headers, binary_part(body, 0, content_length))
        else
          {:ok, chunk} = :gen_tcp.recv(socket, 0, 5_000)
          recv_request(socket, buffer <> chunk)
        end

      :nomatch ->
        {:ok, chunk} = :gen_tcp.recv(socket, 0, 5_000)
        recv_request(socket, buffer <> chunk)
    end
  end

  defp parse_request(headers, body) do
    [request_line | _rest] = String.split(headers, "\r\n", trim: true)
    [method, path, _http_version] = String.split(request_line, " ", parts: 3)
    {:ok, %{method: method, path: path, body: body}}
  end

  defp content_length(headers) do
    headers
    |> String.split("\r\n", trim: true)
    |> Enum.find_value(0, fn line ->
      case String.split(line, ":", parts: 2) do
        [name, value] ->
          if String.downcase(name) == "content-length" do
            value |> String.trim() |> String.to_integer()
          else
            false
          end

        _other ->
          false
      end
    end)
  end

  defp send_json(socket, status, body) do
    :gen_tcp.send(socket, http_response(status, body))
  end

  defp http_response(status, body) do
    status_line =
      case status do
        200 -> "HTTP/1.1 200 OK\r\n"
        404 -> "HTTP/1.1 404 Not Found\r\n"
        500 -> "HTTP/1.1 500 Internal Server Error\r\n"
      end

    [
      status_line,
      "content-type: application/json\r\n",
      "content-length: ",
      Integer.to_string(byte_size(body)),
      "\r\n",
      "connection: close\r\n",
      "\r\n",
      body
    ]
  end

  defp chat_completion_response(model, response_text) do
    escaped_model = json_escape(model)
    escaped_text = json_escape(response_text)

    """
    {"id":"chatcmpl_fake_ollama","object":"chat.completion","model":"#{escaped_model}","choices":[{"index":0,"finish_reason":"stop","message":{"role":"assistant","content":"#{escaped_text}"}}],"usage":{"prompt_tokens":12,"completion_tokens":8,"total_tokens":20}}
    """
    |> String.trim()
  end

  defp models_response(models) do
    entries =
      models
      |> Enum.map(fn model -> ~s({"name":"#{json_escape(model)}"}) end)
      |> Enum.join(",")

    ~s({"models":[#{entries}]})
  end

  defp read_models(state_dir, filename) do
    state_dir
    |> Path.join(filename)
    |> File.read()
    |> case do
      {:ok, contents} ->
        contents
        |> String.split("\n", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      {:error, _reason} ->
        []
    end
  end

  defp read_value(state_dir, filename, default) do
    state_dir
    |> Path.join(filename)
    |> File.read()
    |> case do
      {:ok, value} -> String.trim(value)
      {:error, _reason} -> default
    end
  end

  defp extract_json_string(body, key) when is_binary(body) do
    case Regex.run(~r/"#{Regex.escape(key)}"\s*:\s*"([^"]*)"/, body) do
      [_, value] -> value
      _no_match -> nil
    end
  end

  defp json_escape(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
  end
end

SelfHostedInferenceCore.Examples.FakeOllamaService.main()
