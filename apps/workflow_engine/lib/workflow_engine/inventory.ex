defmodule WorkflowEngine.Inventory do
  @moduledoc """
  Builds a source-faithful Mission Control inventory across canonical workflows
  and external runtime sets without inventing workflow IDs or execution state.
  """

  @spec summary(map()) :: map()
  def summary(registry) when is_map(registry) do
    canonical = safe_map(registry["workflows"])
    sets = safe_map(registry["external_runtime_sets"])
    external = external_workflows(registry)
    canonical_count = map_size(canonical)
    external_count = unique_external_total(sets)
    total_count = canonical_count + external_count
    named_count = canonical_count + length(external)

    %{
      "total_count" => total_count,
      "canonical_count" => canonical_count,
      "external_count" => external_count,
      "named_count" => named_count,
      "named_external_count" => length(external),
      "unresolved_count" => max(total_count - named_count, 0),
      "sets" => set_views(sets)
    }
  end

  @spec external_workflows(map()) :: [map()]
  def external_workflows(registry) when is_map(registry) do
    registry
    |> Map.get("external_runtime_sets", %{})
    |> safe_map()
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce(%{}, fn {set_id, set}, acc ->
      set
      |> workflow_entries()
      |> Enum.reduce(acc, fn entry, workflows ->
        id = entry.id

        Map.put_new(workflows, id, %{
          "id" => id,
          "display_name" => display_name(id),
          "type" => "external",
          "domain" => set_id,
          "status" => "REGISTRY_ONLY",
          "source_status" => set["readiness"] || set["status"] || "REGISTERED_EXTERNAL",
          "execution_status" => "EXTERNAL_REGISTRY_ONLY",
          "executable" => false,
          "runtime" => set["runtime"],
          "source_kind" => "external_runtime_set",
          "source_set" => set_id,
          "relationship" => set["relationship"],
          "risk_level" => entry.risk_level,
          "approval_required" => entry.approval_required,
          "runs" => [],
          "last_run" => nil,
          "dependencies" => [],
          "evidence" => nil
        })
      end)
    end)
    |> Map.values()
    |> Enum.sort_by(& &1["id"])
  end

  defp unique_external_total(sets) do
    sets
    |> Enum.reject(fn {_id, set} -> included_in_parent_total?(set) end)
    |> Enum.reduce(0, fn {_id, set}, total -> total + workflow_count(set) end)
  end

  defp set_views(sets) do
    sets
    |> Enum.map(fn {id, set} ->
      own_ids = workflow_ids(set)
      included_ids = included_child_ids(id, sets)
      named_ids = Enum.uniq(own_ids ++ included_ids)
      count = workflow_count(set)

      %{
        "id" => id,
        "runtime" => set["runtime"],
        "relationship" => set["relationship"],
        "readiness" => set["readiness"] || set["status"],
        "workflow_count" => count,
        "named_workflow_count" => min(length(named_ids), count),
        "unresolved_count" => max(count - length(named_ids), 0),
        "counted_in_total" => not included_in_parent_total?(set)
      }
    end)
    |> Enum.sort_by(& &1["id"])
  end

  defp included_child_ids(parent_id, sets) do
    marker = "included_in_#{parent_id}_total"

    sets
    |> Enum.filter(fn {_id, set} -> set[marker] == true end)
    |> Enum.flat_map(fn {_id, set} -> workflow_ids(set) end)
    |> Enum.uniq()
  end

  defp workflow_count(set) do
    cond do
      is_integer(set["total_workflow_count"]) and set["total_workflow_count"] >= 0 ->
        set["total_workflow_count"]

      is_integer(set["workflow_count"]) and set["workflow_count"] >= 0 ->
        set["workflow_count"]

      true ->
        length(workflow_ids(set))
    end
  end

  defp workflow_entries(set) do
    direct =
      case set["workflow_ids"] do
        ids when is_list(ids) ->
          Enum.filter(ids, &is_binary/1)
          |> Enum.map(&%{id: &1, risk_level: nil, approval_required: nil})

        _ ->
          []
      end

    risk_group_entries =
      set
      |> Map.get("risk_groups", %{})
      |> safe_map()
      |> Enum.flat_map(fn {risk_level, group} ->
        group
        |> safe_map()
        |> Map.get("workflows", [])
        |> safe_list()
        |> Enum.filter(&is_binary/1)
        |> Enum.map(fn id ->
          %{
            id: id,
            risk_level: risk_level,
            approval_required: group["approval_required"]
          }
        end)
      end)

    (direct ++ risk_group_entries)
    |> Enum.reduce(%{}, fn entry, acc -> Map.put_new(acc, entry.id, entry) end)
    |> Map.values()
  end

  defp workflow_ids(set), do: workflow_entries(set) |> Enum.map(& &1.id) |> Enum.uniq()

  defp included_in_parent_total?(set) do
    Enum.any?(set, fn
      {key, true} when is_binary(key) ->
        String.starts_with?(key, "included_in_") and String.ends_with?(key, "_total")

      _ ->
        false
    end)
  end

  defp display_name(id) do
    id
    |> String.replace("_", " ")
    |> String.replace("-", " ")
    |> String.capitalize()
  end

  defp safe_map(value) when is_map(value), do: value
  defp safe_map(_), do: %{}
  defp safe_list(value) when is_list(value), do: value
  defp safe_list(_), do: []
end
