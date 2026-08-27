defmodule ShadowOpsCore.Adapters.OpenCodeAdapter do
  @moduledoc """
  Governed local OpenCode adapter with remote-only model inference.

  Execution is non-interactive (`opencode run`) and never enables OpenCode's
  auto-approval flag. The adapter accepts only bounded prompts, an explicit
  remote provider/model, and project directories below explicitly allowed local roots.
  """
  @behaviour ShadowOpsCore.Adapters.RuntimeAdapter

  alias ShadowOpsCore.{Evidence, WorkflowSource}

  @max_prompt_bytes 32_000
  @max_output_bytes 128_000
  @default_timeout_ms 120_000
  @forbidden_local_model_prefixes ["ollama/", "local/", "lmstudio/", "llamacpp/", "llama.cpp/"]
  @remote_model_pattern ~r/^[A-Za-z0-9._-]+\/[A-Za-z0-9._:#@\/-]+$/

  @impl true
  def discover(_opts \\ []) do
    executable = executable()

    with {:ok, registry} <- WorkflowSource.load(),
         set when is_map(set) <- registry["external_runtime_sets"]["opencode_standard"] do
      {:ok,
       [
         %{
           id: "opencode_standard",
           source: "opencode",
           executable: executable,
           reachable: is_binary(executable),
           workflow_count: set["workflow_count"],
           workflow_ids: set["workflow_ids"]
         }
       ]}
    else
      _ -> {:error, :opencode_runtime_set_unavailable}
    end
  end

  @impl true
  def status(opts \\ []) do
    case discover(opts) do
      {:ok, [row | _]} ->
        cond do
          not row.reachable ->
            %{
              state: "NOT_CONFIGURED",
              discovered: 1,
              reachable: false,
              reason: "opencode_not_found",
              model_policy: "REMOTE_ONLY"
            }

          is_list(row.workflow_ids) ->
            %{
              state: "AVAILABLE",
              discovered: 1,
              reachable: true,
              reason: nil,
              model_policy: "REMOTE_ONLY"
            }

          true ->
            %{
              state: "DEGRADED",
              discovered: 1,
              reachable: true,
              reason: "workflow_ids_not_imported",
              model_policy: "REMOTE_ONLY"
            }
        end

      {:error, reason} ->
        %{
          state: "UNAVAILABLE",
          discovered: 0,
          reachable: false,
          reason: inspect(reason),
          model_policy: "REMOTE_ONLY"
        }
    end
  end

  @impl true
  def validate(%{executable: executable}) when is_binary(executable), do: :ok
  def validate(_), do: {:error, :opencode_not_configured}

  @impl true
  def run(resource, input, %{policy_decision: decision}) when decision in ["AUTO", "APPROVED"] do
    with :ok <- validate(resource),
         {:ok, prompt} <- prompt(input),
         {:ok, project_dir} <- project_dir(input),
         {:ok, model} <- remote_model(input),
         {:ok, args} <- args(input, prompt, model),
         {:ok, output} <- execute(resource.executable, args, project_dir, timeout_ms(input)) do
      {:ok,
       %{
         status: "COMPLETED",
         runtime: "opencode",
         model: model,
         execution_policy: "REMOTE_ONLY",
         output: truncate(output),
         real_data: true,
         synthetic: false,
         reachable: true
       }}
    end
  end

  def run(_, _, _), do: {:error, :policy_decision_required}

  @impl true
  def stop(_, _), do: {:error, :action_not_allowed}

  @impl true
  def health(%{executable: executable}) when is_binary(executable) do
    case System.cmd(executable, ["--version"], stderr_to_stdout: true) do
      {_output, 0} -> %{status: "PASS", reachable: true}
      {_output, code} -> %{status: "FAIL", reachable: false, exit_code: code}
    end
  rescue
    _ -> %{status: "FAIL", reachable: false}
  end

  def health(_), do: %{status: "FAIL", reachable: false}

  @impl true
  def evidence(row) do
    ids_imported = is_list(Map.get(row, :workflow_ids))
    reachable = Map.get(row, :reachable) == true

    Evidence.build(
      "workflow:opencode_standard",
      "opencode",
      [
        %{
          gate: "runtime_binary",
          result: if(reachable, do: "PASS", else: "FAIL"),
          evidence_ref: "runtime:opencode"
        },
        %{
          gate: "workflow_ids",
          result: if(ids_imported, do: "PASS", else: "NOT_ASSESSED"),
          evidence_ref: "registry:opencode_standard"
        },
        %{
          gate: "model_policy",
          result: "PASS",
          evidence_ref: "policy:remote_only"
        }
      ],
      "local OpenCode orchestration, remote-only inference, and canonical workflow registry"
    )
  end

  defp executable do
    case System.get_env("SHADOWOPS_OPENCODE_BIN") do
      value when is_binary(value) and value != "" -> resolve_executable(value)
      _ -> System.find_executable("opencode")
    end
  end

  defp resolve_executable(value) do
    expanded = Path.expand(value)

    cond do
      Path.type(value) == :absolute and File.regular?(expanded) -> expanded
      true -> System.find_executable(value)
    end
  end

  defp prompt(input) when is_map(input) do
    value = value(input, :prompt) || value(input, :task)

    if is_binary(value) and byte_size(value) in 1..@max_prompt_bytes,
      do: {:ok, value},
      else: {:error, :invalid_prompt}
  end

  defp prompt(_), do: {:error, :invalid_prompt}

  defp args(input, prompt, model) do
    with {:ok, agent_args} <- optional_flag(input, :agent, "--agent") do
      {:ok, ["run", "--format", "json"] ++ agent_args ++ ["--model", model, prompt]}
    end
  end

  defp optional_flag(input, key, flag) do
    case value(input, key) do
      nil -> {:ok, []}
      value when is_binary(value) and byte_size(value) in 1..200 -> {:ok, [flag, value]}
      _ -> {:error, {:invalid_option, key}}
    end
  end

  defp remote_model(input) when is_map(input) do
    model = value(input, :model) || System.get_env("SHADOWOPS_CODER_MODEL")

    cond do
      not is_binary(model) or byte_size(model) not in 1..200 ->
        {:error, :remote_model_required}

      not Regex.match?(@remote_model_pattern, model) ->
        {:error, :invalid_remote_model}

      local_model?(model) ->
        {:error, :local_model_forbidden}

      true ->
        {:ok, model}
    end
  end

  defp local_model?(model) do
    normalized = String.downcase(model)
    Enum.any?(@forbidden_local_model_prefixes, &String.starts_with?(normalized, &1))
  end

  defp project_dir(input) do
    requested = value(input, :project_dir) || File.cwd!()
    path = Path.expand(requested)

    cond do
      not File.dir?(path) -> {:error, :project_dir_missing}
      Enum.any?(allowed_roots(), &inside_root?(path, &1)) -> {:ok, path}
      true -> {:error, :project_dir_not_allowlisted}
    end
  end

  defp allowed_roots do
    default = Path.join(System.user_home!(), "Projects")

    System.get_env("SHADOWOPS_OPENCODE_ALLOWED_ROOTS", default)
    |> String.split(":", trim: true)
    |> Enum.map(&Path.expand/1)
  end

  defp inside_root?(path, root), do: path == root or String.starts_with?(path, root <> "/")

  defp timeout_ms(input) do
    case value(input, :timeout_ms) do
      timeout when is_integer(timeout) and timeout in 1_000..600_000 -> timeout
      _ -> @default_timeout_ms
    end
  end

  defp execute(executable, args, project_dir, timeout) do
    task =
      Task.async(fn ->
        System.cmd(executable, args, cd: project_dir, stderr_to_stdout: true)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, 0}} -> {:ok, output}
      {:ok, {output, code}} -> {:error, {:opencode_failed, code, truncate(output)}}
      nil -> {:error, :opencode_timeout}
    end
  rescue
    error -> {:error, {:opencode_execution_failed, Exception.message(error)}}
  end

  defp truncate(value) when byte_size(value) <= @max_output_bytes, do: value
  defp truncate(value), do: binary_part(value, 0, @max_output_bytes) <> "\n[TRUNCATED]"

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
