defmodule ShadowOpsCore.Adapters.GitHubActionsAdapter do
  @moduledoc "Evidence-backed GitHub Actions adapter using the authenticated GitHub CLI as the real transport."
  @behaviour ShadowOpsCore.Adapters.RuntimeAdapter

  alias ShadowOpsCore.{Evidence, WorkflowManifest, WorkflowSource}

  @repo_env "SHADOWOPS_GITHUB_REPOSITORY"
  @ref_env "SHADOWOPS_GITHUB_REF"
  @safe_repo ~r/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/
  @safe_ref ~r/^[A-Za-z0-9._\/-]+$/
  @safe_input_key ~r/^[A-Za-z0-9_-]+$/

  @impl true
  def discover(opts \\ []) do
    overlay = Keyword.get(opts, :local_workflow_overlay)

    with {:ok, registry} <- WorkflowSource.load(overlay) do
      rows =
        registry["workflows"]
        |> Enum.flat_map(fn {id, workflow} ->
          case WorkflowManifest.from_registry(id, workflow) do
            {:ok, %{source: "github_actions"} = manifest} ->
              [
                Map.put(
                  manifest,
                  :metadata,
                  Map.put(manifest.metadata, :definition, workflow["definition"])
                )
              ]

            _ ->
              []
          end
        end)

      {:ok, rows}
    end
  end

  @impl true
  def status(opts \\ []) do
    case discover(opts) do
      {:ok, rows} ->
        configured = Enum.reject(rows, &disabled?/1)
        definitions_valid = Enum.count(configured, &(validate(&1) == :ok))
        connectivity = github_probe(opts)

        %{
          state:
            if(
              configured != [] and definitions_valid == length(configured) and
                match?({:ok, _}, connectivity),
              do: "READY",
              else: "DEGRADED"
            ),
          discovered: length(rows),
          configured: length(configured),
          disabled: length(rows) - length(configured),
          definitions_valid: definitions_valid,
          repository: connected_repository(connectivity),
          source: "github_cli_api",
          reason: status_reason(configured, definitions_valid, connectivity)
        }

      {:error, reason} ->
        %{state: "UNAVAILABLE", discovered: 0, reason: inspect(reason), source: "github_cli_api"}
    end
  end

  @impl true
  def validate(%WorkflowManifest{metadata: %{registry_status: status}})
      when status in ["DISABLED_BY_CONFIGURATION", "REGISTRY_ONLY"],
      do: {:error, :disabled_by_configuration}

  def validate(%WorkflowManifest{metadata: %{definition: definition}})
      when is_binary(definition) and definition != "" do
    if File.regular?(Path.join(root(), definition)),
      do: :ok,
      else: {:error, :definition_unavailable}
  end

  def validate(_), do: {:error, :invalid_manifest}

  @impl true
  def run(
        %WorkflowManifest{} = manifest,
        input,
        %{policy_decision: decision} = context
      )
      when decision in ["AUTO", "APPROVED"] and is_map(input) do
    opts = runtime_opts(input, context)

    case run_workflow(manifest, input, opts) do
      {:ok, result} ->
        {:ok, Map.put(result, :accepted, true)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def run(_, _, _), do: {:error, :policy_decision_required}

  @impl true
  def stop(_, _), do: {:error, :stop_not_supported}

  @impl true
  def health(manifest) do
    local = validate(manifest)
    remote = github_probe([])

    %{
      status: if(local == :ok and match?({:ok, _}, remote), do: "PASS", else: "FAIL"),
      definition: if(local == :ok, do: "PASS", else: "FAIL"),
      repository: connected_repository(remote),
      source: "github_cli_api"
    }
  end

  @impl true
  def evidence(%WorkflowManifest{id: id, metadata: %{definition: definition}} = manifest) do
    remote = github_probe([])

    Evidence.build(
      "workflow:" <> id,
      "github_actions",
      [
        %{
          gate: "definition",
          result: pass(validate(manifest) == :ok),
          evidence_ref: definition
        },
        %{
          gate: "github_repository",
          result: pass(match?({:ok, _}, remote)),
          evidence_ref: connected_repository(remote) || "github_repository_unavailable"
        }
      ],
      "canonical workflow registry plus repository file plus authenticated GitHub CLI API probe"
    )
  end

  defp run_workflow(manifest, input, opts) do
    with :ok <- validate(manifest),
         :ok <- reject_synthetic(manifest),
         {:ok, repository} <- repository(opts),
         {:ok, ref} <- resolve_ref(input, opts),
         {:ok, definition} <- resolve_definition(manifest),
         {:ok, input_args} <- workflow_input_args(input),
         {:ok, _output} <-
           gh(
             ["workflow", "run", definition, "--repo", repository, "--ref", ref] ++ input_args,
             opts
           ) do
      {:ok,
       %{
         workflow: manifest.id,
         definition: definition,
         repository: repository,
         ref: ref,
         transport: "gh workflow run",
         real_data: true,
         synthetic: false
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_definition(%WorkflowManifest{metadata: %{definition: definition}})
       when is_binary(definition) and definition != "",
       do: {:ok, definition}

  defp resolve_definition(_), do: {:error, :github_workflow_definition_missing}

  defp workflow_input_args(input) do
    inputs = value(input, :inputs, %{})

    cond do
      not is_map(inputs) ->
        {:error, :github_workflow_inputs_must_be_a_map}

      Enum.all?(inputs, fn {key, value} -> safe_input?(key, value) end) ->
        {:ok,
         Enum.flat_map(inputs, fn {key, value} ->
           ["-f", "#{key}=#{value}"]
         end)}

      true ->
        {:error, :invalid_github_workflow_input}
    end
  end

  defp safe_input?(key, value) do
    key = to_string(key)

    Regex.match?(@safe_input_key, key) and
      (is_binary(value) or is_integer(value) or is_float(value) or is_boolean(value))
  end

  defp github_probe(opts) do
    with {:ok, repository} <- repository(opts),
         {:ok, output} <- gh(["api", "repos/#{repository}", "--jq", ".full_name"], opts),
         true <- String.trim(output) == repository do
      {:ok, %{repository: repository, reachable: true, real_data: true, synthetic: false}}
    else
      false -> {:error, :github_repository_identity_mismatch}
      {:error, _} = error -> error
    end
  end

  defp repository(opts) do
    candidate = Keyword.get(opts, :repository) || System.get_env(@repo_env)

    case candidate do
      nil -> detect_repository(opts)
      "" -> detect_repository(opts)
      repository -> validate_repository(repository)
    end
  end

  defp detect_repository(opts) do
    case command("git", ["config", "--get", "remote.origin.url"], [cd: root()], opts) do
      {:ok, remote} -> parse_repository_remote(remote)
      {:error, _} -> {:error, :github_repository_not_configured}
    end
  end

  defp parse_repository_remote(remote) do
    remote = String.trim(remote)

    case Regex.run(~r{github\.com[:/]([^/\s]+/[^/\s]+?)(?:\.git)?$}, remote,
           capture: :all_but_first
         ) do
      [repository] -> validate_repository(String.trim_trailing(repository, ".git"))
      _ -> {:error, :unsupported_github_remote}
    end
  end

  defp validate_repository(repository) when is_binary(repository) do
    if Regex.match?(@safe_repo, repository),
      do: {:ok, repository},
      else: {:error, :invalid_github_repository}
  end

  defp validate_repository(_), do: {:error, :invalid_github_repository}

  defp resolve_ref(input, opts) do
    candidate =
      value(input, :ref) || Keyword.get(opts, :ref) || System.get_env(@ref_env) ||
        current_ref(opts)

    cond do
      not is_binary(candidate) or candidate == "" -> {:error, :github_ref_required}
      Regex.match?(@safe_ref, candidate) -> {:ok, candidate}
      true -> {:error, :invalid_github_ref}
    end
  end

  defp current_ref(opts) do
    case command("git", ["branch", "--show-current"], [cd: root()], opts) do
      {:ok, ref} -> String.trim(ref)
      {:error, _} -> nil
    end
  end

  defp runtime_opts(input, context) do
    [
      repository: value(input, :repository_ref) || value(context, :github_repository),
      ref: value(input, :ref) || value(context, :github_ref),
      runner: value(context, :github_runner)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp gh(args, opts), do: command("gh", args, [stderr_to_stdout: true], opts)

  defp command(executable, args, command_opts, opts) do
    runner = Keyword.get(opts, :runner, &System.cmd/3)

    try do
      case runner.(executable, args, command_opts) do
        {output, 0} -> {:ok, output}
        {_output, code} -> {:error, {:command_exit, executable, code}}
      end
    rescue
      _ -> {:error, {:command_unavailable, executable}}
    catch
      :exit, _ -> {:error, {:command_unavailable, executable}}
    end
  end

  defp reject_synthetic(%WorkflowManifest{synthetic: true}),
    do: {:error, :synthetic_workflow_blocked}

  defp reject_synthetic(_), do: :ok

  defp disabled?(%WorkflowManifest{metadata: %{registry_status: status}}),
    do: status in ["DISABLED_BY_CONFIGURATION", "REGISTRY_ONLY"]

  defp disabled?(_), do: false

  defp connected_repository({:ok, %{repository: repository}}), do: repository
  defp connected_repository(_), do: nil

  defp status_reason([], _definitions_valid, _connectivity), do: "github_workflow_not_configured"

  defp status_reason(configured, definitions_valid, _connectivity)
       when definitions_valid != length(configured),
       do: "github_workflow_definition_drift"

  defp status_reason(_configured, _definitions_valid, {:error, reason}),
    do: "github_source_unavailable:" <> inspect(reason)

  defp status_reason(_configured, _definitions_valid, {:ok, _}), do: nil

  defp value(map, key, default \\ nil)

  defp value(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp value(_, _, default), do: default

  defp root, do: Path.expand("../../../../..", __DIR__)
  defp pass(true), do: "PASS"
  defp pass(false), do: "FAIL"
end
