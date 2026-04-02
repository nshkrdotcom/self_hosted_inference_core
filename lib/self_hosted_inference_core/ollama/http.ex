defmodule SelfHostedInferenceCore.Ollama.HTTP do
  @moduledoc false

  @default_timeout_ms 5_000

  @type request_error ::
          {:http_error, pos_integer(), map()}
          | {:invalid_response, term()}
          | {:invalid_json, term()}
          | {:invalid_http_response, term()}
          | term()

  @spec fetch_version(String.t(), keyword()) ::
          {:ok, String.t() | nil} | {:error, request_error()}
  def fetch_version(root_url, opts \\ []) when is_binary(root_url) do
    case request(:get, root_url, "/api/version", nil, opts) do
      {:ok, %{"version" => version}} when is_binary(version) ->
        {:ok, String.trim(version)}

      {:ok, _other} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec show_model(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, request_error()}
  def show_model(root_url, model_identity, opts \\ [])
      when is_binary(root_url) and is_binary(model_identity) do
    request(
      :post,
      root_url,
      "/api/show",
      %{"model" => String.trim(model_identity)},
      opts
    )
  end

  @spec running_models(String.t(), keyword()) :: {:ok, [map()]} | {:error, request_error()}
  def running_models(root_url, opts \\ []) when is_binary(root_url) do
    case request(:get, root_url, "/api/ps", nil, opts) do
      {:ok, %{"models" => models}} when is_list(models) ->
        {:ok, models}

      {:ok, other} ->
        {:error, {:invalid_response, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec request(atom(), String.t(), String.t(), map() | nil, keyword()) ::
          {:ok, map()} | {:error, request_error()}
  def request(method, root_url, path, payload, opts)
      when method in [:get, :post] and is_binary(root_url) and is_binary(path) and is_list(opts) do
    case Keyword.get(opts, :ollama_http) do
      http when is_function(http, 4) ->
        request_with_stub(http, method, path, payload, opts)

      nil ->
        with :ok <- ensure_http_apps_started(),
             {:ok, body} <- do_httpc_request(method, root_url, path, payload, opts) do
          decode_http_body(body)
        end
    end
  end

  defp request_with_stub(http, method, path, payload, opts) when is_function(http, 4) do
    case http.(method, path, payload, opts) do
      {:ok, status, body} when is_integer(status) and is_map(body) and status in 200..299 ->
        {:ok, body}

      {:ok, status, body} when is_integer(status) and is_map(body) ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:invalid_http_stub_response, other}}
    end
  end

  defp ensure_http_apps_started do
    with {:ok, _} <- Application.ensure_all_started(:inets),
         {:ok, _} <- Application.ensure_all_started(:ssl) do
      :ok
    end
  end

  defp do_httpc_request(method, root_url, path, payload, opts) do
    url = String.to_charlist(String.trim_trailing(root_url, "/") <> path)
    timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    http_opts = [timeout: timeout]
    request_opts = [body_format: :binary]

    request =
      case method do
        :get ->
          {url, []}

        :post ->
          {url, [{~c"content-type", ~c"application/json"}], ~c"application/json",
           Jason.encode!(payload)}
      end

    case :httpc.request(method, request, http_opts, request_opts) do
      {:ok, {{_http_version, status, _reason_phrase}, _headers, body}} when status in 200..299 ->
        {:ok, body}

      {:ok, {{_http_version, status, _reason_phrase}, _headers, body}} ->
        with {:ok, decoded} <- decode_http_body(body) do
          {:error, {:http_error, status, decoded}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_http_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      {:ok, other} -> {:error, {:invalid_response, other}}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end
end
