defmodule ShadowOpsCore.Adapters.OllamaAdapter do
  @moduledoc """
  Governed adapter for an explicitly allowlisted Ollama HTTP endpoint.

  The default endpoint is loopback-only. Remote hosts require an explicit
  `SHADOWOPS_OLLAMA_ALLOWED_HOSTS` entry. Generation is bounded, non-streaming,
  and never promotes availability without a successful live probe.
  """
  @behaviour ShadowOpsCore.Adapters.RuntimeAdapter

  alias ShadowOpsCore.Evidence

  @default_url "http://127.0.0.1:11434"
  @default_timeout_ms 120_000
  @max_prompt_bytes 64_000
  @max_response_bytes 256_000
  @model_pattern ~r/^[A-Za-z0-9][A-Za-z0-9._:\/-]{0,199}$/

  @impl true
  def discover(opts \\ []) do
    with {:ok, base_url} <- base_url(opts),
         {:ok, payload} <- request(:get, base_url <> "/api/tags", nil, timeout_ms(opts)),
         {:ok, models} <- decode_models(payload) do
      {:ok,
       Enum.map(models, fn model ->
         %{
           id: model,
           name: model,
           source: "ollama",
           base_url: base_url,
           reachable: true,
           real_data: true,
           synthetic: false
         }
       end)}
    end
  end

  @impl true
  def status(opts \\ []) do
    case discover(opts) do
      {:ok, rows} ->
        %{
          state: "AVAILABLE",
          discovered: length(rows),
          reachable: true,
          real_data: true,
          synthetic: false,
          reason: nil
        }

      {:error, :ollama_host_not_allowlisted} ->
        %{
          state: "NOT_CONFIGURED",
          discovered: 0,
          reachable: false,
          real_data: false,
          synthetic: false,
          reason: "ollama_host_not_allowlisted"
        }

      {:error, reason} ->
        %{
          state: "UNAVAILABLE",
          discovered: 0,
          reachable: false,
          real_data: false,
          synthetic: false,
          reason: inspect(reason)
        }
    end
  end

  @impl true
  def validate(%{name: model, base_url: base_url})
      when is_binary(model) and is_binary(base_url) do
    if Regex.match?(@model_pattern, model), do: :ok, else: {:error, :invalid_model}
  end

  def validate(_), do: {:error, :invalid_model}

  @impl true
  def run(resource, input, %{policy_decision: decision}) when decision in ["AUTO", "APPROVED"] do
    with :ok <- validate(resource),
         {:ok, prompt} <- prompt(input),
         :ok <- requested_model_matches(resource, input),
         body <- Jason.encode!(%{model: resource.name, prompt: prompt, stream: false}),
         {:ok, payload} <-
           request(:post, resource.base_url <> "/api/generate", body, timeout_ms(input)),
         {:ok, response} <- decode_generation(payload) do
      {:ok,
       %{
         status: "COMPLETED",
         runtime: "ollama",
         model: resource.name,
         response: response,
         real_data: true,
         synthetic: false,
         reachable: true
       }}
    end
  end

  def run(_, _, _), do: {:error, :policy_decision_required}

  @impl true
  def stop(%{name: model}, %{policy_decision: decision}) when decision in ["AUTO", "APPROVED"] do
    case executable() do
      nil -> {:error, :ollama_cli_not_configured}
      executable -> stop_model(executable, model)
    end
  end

  def stop(_, _), do: {:error, :policy_decision_required}

  @impl true
  def health(%{base_url: base_url}) when is_binary(base_url) do
    case request(:get, base_url <> "/api/tags", nil, 5_000) do
      {:ok, _} -> %{status: "PASS", reachable: true}
      {:error, reason} -> %{status: "FAIL", reachable: false, reason: inspect(reason)}
    end
  end

  def health(_), do: %{status: "FAIL", reachable: false}

  @impl true
  def evidence(%{name: model, base_url: base_url}) do
    result = health(%{base_url: base_url})

    Evidence.build(
      "model:" <> model,
      "ollama",
      [
        %{
          gate: "ollama_api",
          result: result.status,
          evidence_ref: "ollama:/api/tags"
        }
      ],
      "allowlisted Ollama HTTP endpoint"
    )
  end

  defp base_url(opts) do
    value =
      option(opts, :base_url) || System.get_env("SHADOWOPS_OLLAMA_URL") || @default_url

    with %URI{scheme: "http", host: host, path: path} = uri <- URI.parse(value),
         true <- is_binary(host) and host != "",
         true <- path in [nil, "", "/"],
         true <- host in allowed_hosts() do
      normalized = %URI{uri | path: nil, query: nil, fragment: nil}
      {:ok, URI.to_string(normalized) |> String.trim_trailing("/")}
    else
      false -> {:error, :ollama_host_not_allowlisted}
      _ -> {:error, :invalid_ollama_url}
    end
  end

  defp allowed_hosts do
    System.get_env("SHADOWOPS_OLLAMA_ALLOWED_HOSTS", "127.0.0.1,localhost")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp prompt(input) when is_map(input) do
    value = value(input, :prompt)

    if is_binary(value) and byte_size(value) in 1..@max_prompt_bytes,
      do: {:ok, value},
      else: {:error, :invalid_prompt}
  end

  defp prompt(_), do: {:error, :invalid_prompt}

  defp requested_model_matches(resource, input) do
    case value(input, :model) do
      nil -> :ok
      model when model == resource.name -> :ok
      _ -> {:error, :model_mismatch}
    end
  end

  defp timeout_ms(input) do
    case option(input, :timeout_ms) do
      timeout when is_integer(timeout) and timeout in 1_000..600_000 -> timeout
      _ -> @default_timeout_ms
    end
  end

  defp request(:get, url, nil, timeout) do
    ensure_http_started()

    case :httpc.request(:get, {String.to_charlist(url), []}, request_opts(timeout), body_opts()) do
      {:ok, {{_, code, _}, _headers, body}} when code in 200..299 -> bounded_body(body)
      {:ok, {{_, code, _}, _headers, body}} -> {:error, {:ollama_http_error, code, truncate(body)}}
      {:error, reason} -> {:error, {:ollama_unreachable, reason}}
    end
  end

  defp request(:post, url, body, timeout) when is_binary(body) do
    ensure_http_started()
    request = {String.to_charlist(url), [], ~c"application/json", body}

    case :httpc.request(:post, request, request_opts(timeout), body_opts()) do
      {:ok, {{_, code, _}, _headers, response}} when code in 200..299 -> bounded_body(response)
      {:ok, {{_, code, _}, _headers, response}} ->
        {:error, {:ollama_http_error, code, truncate(response)}}

      {:error, reason} ->
        {:error, {:ollama_unreachable, reason}}
    end
  end

  defp request_opts(timeout), do: [timeout: timeout, connect_timeout: min(timeout, 5_000)]
  defp body_opts, do: [body_format: :binary]

  defp ensure_http_started do
    _ = Application.ensure_all_started(:inets)
    :ok
  end

  defp bounded_body(body) when is_binary(body) and byte_size(body) <= @max_response_bytes,
    do: {:ok, body}

  defp bounded_body(_), do: {:error, :ollama_response_too_large}

  defp decode_models(payload) do
    with {:ok, %{"models" => models}} when is_list(models) <- Jason.decode(payload) do
      names =
        models
        |> Enum.map(&Map.get(&1, "name"))
        |> Enum.filter(&(is_binary(&1) and Regex.match?(@model_pattern, &1)))

      {:ok, names}
    else
      _ -> {:error, :invalid_ollama_tags_response}
    end
  end

  defp decode_generation(payload) do
    with {:ok, %{"response" => response}} when is_binary(response) <- Jason.decode(payload) do
      {:ok, response}
    else
      _ -> {:error, :invalid_ollama_generation_response}
    end
  end

  defp executable do
    case System.get_env("SHADOWOPS_OLLAMA_BIN") do
      value when is_binary(value) and value != "" -> System.find_executable(value) || Path.expand(value)
      _ -> System.find_executable("ollama")
    end
  end

  defp stop_model(executable, model) do
    if Regex.match?(@model_pattern, model) do
      case System.cmd(executable, ["stop", model], stderr_to_stdout: true) do
        {output, 0} -> {:ok, %{status: "STOPPED", model: model, output: truncate(output)}}
        {output, code} -> {:error, {:ollama_stop_failed, code, truncate(output)}}
      end
    else
      {:error, :invalid_model}
    end
  rescue
    error -> {:error, {:ollama_stop_failed, Exception.message(error)}}
  end

  defp truncate(value) when is_binary(value) and byte_size(value) <= @max_response_bytes, do: value
  defp truncate(value) when is_binary(value), do: binary_part(value, 0, @max_response_bytes) <> "\n[TRUNCATED]"
  defp truncate(value), do: inspect(value)

  defp option(opts, key) when is_list(opts), do: Keyword.get(opts, key)
  defp option(opts, key) when is_map(opts), do: value(opts, key)
  defp option(_, _), do: nil

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
