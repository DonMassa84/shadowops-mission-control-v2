defmodule WorkflowEngine.Registry do
  @moduledoc """
  Loads and validates the ShadowOps schema-v2 workflow registry.

  The legacy registry remains untouched during migration. This module is a
  read-only loader until the v2 cutover is explicitly completed.
  """

  alias WorkflowEngine.Registry.Error

  @required_top_level ~w(schema_version registry_name workflows workflow_runs external_runtime_sets)
  @workflow_types ~w(business system)
  @risk_levels ~w(L0 L1 L2 L3)

  def path do
    Application.fetch_env!(:workflow_engine, :registry_path)
  end

  def load(path \\ path()) do
    registry = YamlElixir.read_from_file!(path)

    case validate(registry) do
      :ok -> {:ok, registry}
      {:error, %Error{}} = error -> error
    end
  rescue
    exception ->
      {:error,
       Error.new(:registry_load_failed, [], %{
         path: path,
         reason: Exception.message(exception)
       })}
  end

  def validate(registry) when is_map(registry) do
    with :ok <- validate_required_keys(registry),
         :ok <- validate_schema_version(registry),
         :ok <- validate_registry_name(registry),
         :ok <- validate_collection_types(registry),
         :ok <- validate_workflows(registry["workflows"]),
         :ok <- validate_workflow_runs(registry["workflow_runs"], registry["workflows"]) do
      validate_external_runtime_sets(registry["external_runtime_sets"])
    end
  end

  def validate(value), do: error(:registry_must_be_a_map, [], %{actual: type_of(value)})

  def list_workflows(path \\ path()) do
    with {:ok, registry} <- load(path) do
      registry
      |> Map.fetch!("workflows")
      |> Map.keys()
      |> Enum.sort()
    end
  end

  def summary(path \\ path()) do
    with {:ok, registry} <- load(path) do
      {:ok,
       %{
         schema_version: registry["schema_version"],
         registry_name: registry["registry_name"],
         workflows: map_size(registry["workflows"]),
         workflow_runs: map_size(registry["workflow_runs"]),
         external_runtime_sets: map_size(registry["external_runtime_sets"])
       }}
    end
  end

  defp validate_required_keys(registry) do
    missing = Enum.reject(@required_top_level, &Map.has_key?(registry, &1))

    case missing do
      [] -> :ok
      keys -> error(:missing_top_level_keys, [], %{missing: keys})
    end
  end

  defp validate_schema_version(%{"schema_version" => 2}), do: :ok

  defp validate_schema_version(%{"schema_version" => version}) do
    error(:unsupported_schema_version, ["schema_version"], %{actual: version, expected: 2})
  end

  defp validate_registry_name(%{"registry_name" => value})
       when is_binary(value) and byte_size(value) > 0,
       do: :ok

  defp validate_registry_name(%{"registry_name" => value}) do
    error(:invalid_registry_name, ["registry_name"], %{actual: value})
  end

  defp validate_collection_types(registry) do
    Enum.reduce_while(~w(workflows workflow_runs external_runtime_sets), :ok, fn key, :ok ->
      if is_map(registry[key]) do
        {:cont, :ok}
      else
        {:halt, error(:collection_must_be_a_map, [key], %{actual: type_of(registry[key])})}
      end
    end)
  end

  defp validate_workflows(workflows) do
    Enum.reduce_while(workflows, :ok, fn {workflow_id, workflow}, :ok ->
      case validate_workflow(workflow_id, workflow) do
        :ok -> {:cont, :ok}
        {:error, %Error{}} = validation_error -> {:halt, validation_error}
      end
    end)
  end

  defp validate_workflow(workflow_id, workflow)
       when is_binary(workflow_id) and byte_size(workflow_id) > 0 and is_map(workflow) do
    base = ["workflows", workflow_id]

    with :ok <- require_string(workflow, "type", base),
         :ok <- require_string(workflow, "domain", base),
         :ok <- require_string(workflow, "status", base),
         :ok <- validate_workflow_type(workflow, base),
         :ok <- validate_workflow_runtime_contract(workflow, base),
         :ok <- validate_registry_argv(workflow, base),
         :ok <- validate_optional_configuration_contract(workflow, base) do
      validate_verified_runtime_contract(workflow, base)
    end
  end

  defp validate_workflow(workflow_id, workflow) do
    error(:invalid_workflow_definition, ["workflows", to_string(workflow_id)], %{
      id: workflow_id,
      actual: type_of(workflow)
    })
  end

  defp validate_workflow_type(%{"type" => type}, _base) when type in @workflow_types, do: :ok

  defp validate_workflow_type(%{"type" => type}, base) do
    error(:invalid_workflow_type, base ++ ["type"], %{actual: type, allowed: @workflow_types})
  end

  defp validate_workflow_runtime_contract(%{"type" => "system"} = workflow, base) do
    with :ok <- require_string(workflow, "runtime", base) do
      require_string(workflow, "definition", base)
    end
  end

  defp validate_workflow_runtime_contract(%{"type" => "business"} = workflow, base) do
    runtime = workflow["target_runtime"] || workflow["runtime"]

    if is_binary(runtime) and byte_size(runtime) > 0 do
      :ok
    else
      error(:missing_business_target_runtime, base, %{
        expected_one_of: ["target_runtime", "runtime"]
      })
    end
  end

  defp validate_registry_argv(%{"argv" => argv}, base) when is_list(argv) do
    if Enum.all?(argv, &is_binary/1) do
      :ok
    else
      error(:invalid_workflow_argv, base ++ ["argv"], %{expected: "list of strings"})
    end
  end

  defp validate_registry_argv(%{"argv" => argv}, base) do
    error(:invalid_workflow_argv, base ++ ["argv"], %{
      actual: type_of(argv),
      expected: "list of strings"
    })
  end

  defp validate_registry_argv(_workflow, _base), do: :ok

  defp validate_optional_configuration_contract(
         %{
           "status" => "DISABLED_BY_CONFIGURATION",
           "optional" => true,
           "configuration_status" => "NOT_CONFIGURED",
           "disabled_reason" => reason
         },
         _base
       )
       when is_binary(reason) and byte_size(reason) > 0,
       do: :ok

  defp validate_optional_configuration_contract(
         %{"status" => "DISABLED_BY_CONFIGURATION"} = workflow,
         base
       ) do
    error(:invalid_optional_configuration_contract, base, %{
      optional: workflow["optional"],
      configuration_status: workflow["configuration_status"],
      disabled_reason: workflow["disabled_reason"]
    })
  end

  defp validate_optional_configuration_contract(_workflow, _base), do: :ok

  defp validate_verified_runtime_contract(
         %{"status" => "VERIFIED_EXECUTABLE", "runtime" => runtime},
         base
       )
       when is_binary(runtime) do
    if Path.type(runtime) == :absolute and Path.expand(runtime) == runtime do
      :ok
    else
      error(:invalid_verified_runtime, base ++ ["runtime"], %{actual: runtime})
    end
  end

  defp validate_verified_runtime_contract(%{"status" => "VERIFIED_EXECUTABLE"}, base) do
    error(:invalid_verified_runtime, base ++ ["runtime"], %{actual: nil})
  end

  defp validate_verified_runtime_contract(_workflow, _base), do: :ok

  defp validate_workflow_runs(runs, workflows) do
    Enum.reduce_while(runs, :ok, fn {run_id, run}, :ok ->
      case validate_workflow_run(run_id, run, workflows) do
        :ok -> {:cont, :ok}
        {:error, %Error{}} = validation_error -> {:halt, validation_error}
      end
    end)
  end

  defp validate_workflow_run(run_id, run, workflows)
       when is_binary(run_id) and byte_size(run_id) > 0 and is_map(run) do
    base = ["workflow_runs", run_id]

    with :ok <- require_string(run, "workflow", base),
         :ok <- require_string(run, "type", base),
         :ok <- require_string(run, "status", base),
         :ok <- require_string(run, "input", base),
         :ok <- validate_run_type(run, base) do
      validate_run_reference(run, workflows, base)
    end
  end

  defp validate_workflow_run(run_id, run, _workflows) do
    error(:invalid_workflow_run, ["workflow_runs", to_string(run_id)], %{
      id: run_id,
      actual: type_of(run)
    })
  end

  defp validate_run_type(%{"type" => "instance"}, _base), do: :ok

  defp validate_run_type(%{"type" => type}, base) do
    error(:invalid_workflow_run_type, base ++ ["type"], %{actual: type, expected: "instance"})
  end

  defp validate_run_reference(%{"workflow" => workflow_id}, workflows, _base)
       when is_binary(workflow_id) and is_map_key(workflows, workflow_id),
       do: :ok

  defp validate_run_reference(%{"workflow" => workflow_id}, _workflows, base) do
    error(:unknown_workflow_reference, base ++ ["workflow"], %{workflow: workflow_id})
  end

  defp validate_external_runtime_sets(sets) do
    Enum.reduce_while(sets, :ok, fn {set_id, set}, :ok ->
      case validate_external_runtime_set(set_id, set) do
        :ok -> {:cont, :ok}
        {:error, %Error{}} = validation_error -> {:halt, validation_error}
      end
    end)
  end

  defp validate_external_runtime_set(set_id, set)
       when is_binary(set_id) and byte_size(set_id) > 0 and is_map(set) do
    base = ["external_runtime_sets", set_id]

    with :ok <- validate_optional_workflow_count(set, base),
         :ok <- validate_risk_distribution(set, base),
         :ok <- validate_blocker_distribution(set, base) do
      validate_whatsapp_pack(set_id, set, base)
    end
  end

  defp validate_external_runtime_set(set_id, set) do
    error(:invalid_external_runtime_set, ["external_runtime_sets", to_string(set_id)], %{
      id: set_id,
      actual: type_of(set)
    })
  end

  defp validate_optional_workflow_count(%{"workflow_count" => count}, _base)
       when is_integer(count) and count >= 0,
       do: :ok

  defp validate_optional_workflow_count(%{"workflow_count" => count}, base) do
    error(:invalid_workflow_count, base ++ ["workflow_count"], %{actual: count})
  end

  defp validate_optional_workflow_count(_set, _base), do: :ok

  defp validate_risk_distribution(
         %{"total_workflow_count" => total, "risk_distribution" => distribution},
         base
       )
       when is_integer(total) and total >= 0 and is_map(distribution) do
    with :ok <- validate_risk_values(distribution, base) do
      actual = Enum.sum(Enum.map(@risk_levels, &Map.fetch!(distribution, &1)))
      compare_total(total, actual, base ++ ["risk_distribution"], :risk_total_mismatch)
    end
  end

  defp validate_risk_distribution(%{"total_workflow_count" => total}, base) do
    error(:invalid_risk_distribution, base ++ ["risk_distribution"], %{
      total_workflow_count: total
    })
  end

  defp validate_risk_distribution(_set, _base), do: :ok

  defp validate_risk_values(distribution, base) do
    missing = Enum.reject(@risk_levels, &Map.has_key?(distribution, &1))

    cond do
      missing != [] ->
        error(:missing_risk_levels, base ++ ["risk_distribution"], %{missing: missing})

      Enum.any?(@risk_levels, fn level ->
        value = distribution[level]
        not (is_integer(value) and value >= 0)
      end) ->
        error(:invalid_risk_level_count, base ++ ["risk_distribution"], distribution)

      true ->
        :ok
    end
  end

  defp validate_blocker_distribution(%{"blockers" => blockers}, base) when is_map(blockers) do
    total = blockers["total"]
    counts = blockers |> Map.delete("total") |> Map.values()

    cond do
      not (is_integer(total) and total >= 0) ->
        error(:invalid_blocker_total, base ++ ["blockers", "total"], %{actual: total})

      Enum.any?(counts, fn count -> not (is_integer(count) and count >= 0) end) ->
        error(:invalid_blocker_count, base ++ ["blockers"], blockers)

      true ->
        compare_total(total, Enum.sum(counts), base ++ ["blockers"], :blocker_total_mismatch)
    end
  end

  defp validate_blocker_distribution(_set, _base), do: :ok

  defp validate_whatsapp_pack("whatsapp_agent_pack", set, base) do
    count = set["workflow_count"]
    groups = set["risk_groups"]

    with :ok <- validate_whatsapp_groups(groups, base),
         workflows <- whatsapp_workflows(groups),
         :ok <-
           compare_total(
             count,
             length(workflows),
             base ++ ["risk_groups"],
             :workflow_count_mismatch
           ) do
      validate_unique_workflows(workflows, base)
    end
  end

  defp validate_whatsapp_pack(_set_id, _set, _base), do: :ok

  defp validate_whatsapp_groups(groups, base) when is_map(groups) do
    Enum.reduce_while(~w(L0 L1 L2), :ok, fn level, :ok ->
      group = groups[level]
      workflows = is_map(group) && group["workflows"]

      if is_list(workflows) and Enum.all?(workflows, &is_binary/1) do
        {:cont, :ok}
      else
        {:halt,
         error(:invalid_whatsapp_risk_group, base ++ ["risk_groups", level], %{
           expected: "map with workflows: [string]"
         })}
      end
    end)
  end

  defp validate_whatsapp_groups(groups, base) do
    error(:invalid_whatsapp_risk_groups, base ++ ["risk_groups"], %{actual: type_of(groups)})
  end

  defp whatsapp_workflows(groups) do
    ~w(L0 L1 L2)
    |> Enum.flat_map(fn level -> groups[level]["workflows"] end)
  end

  defp validate_unique_workflows(workflows, base) do
    duplicates =
      workflows
      |> Enum.frequencies()
      |> Enum.filter(fn {_workflow, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    case duplicates do
      [] ->
        :ok

      values ->
        error(:duplicate_external_workflow_ids, base ++ ["risk_groups"], %{duplicates: values})
    end
  end

  defp compare_total(expected, actual, _path, _code) when expected == actual, do: :ok

  defp compare_total(expected, actual, path, code) do
    error(code, path, %{expected: expected, actual: actual})
  end

  defp require_string(map, key, base) do
    case map[key] do
      value when is_binary(value) and byte_size(value) > 0 -> :ok
      value -> error(:required_string_missing_or_invalid, base ++ [key], %{actual: value})
    end
  end

  defp error(code, path, details), do: {:error, Error.new(code, path, details)}

  defp type_of(value) when is_map(value), do: :map
  defp type_of(value) when is_list(value), do: :list
  defp type_of(value) when is_binary(value), do: :string
  defp type_of(value) when is_integer(value), do: :integer
  defp type_of(value) when is_float(value), do: :float
  defp type_of(value) when is_boolean(value), do: :boolean
  defp type_of(nil), do: nil
  defp type_of(_value), do: :other
end
