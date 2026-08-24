defmodule AgentRuntime.TccImporter do
  @moduledoc """
  Imports the external `shadowmaker-tasks` registry without assuming one exact
  JSON container shape.

  Supported inputs are a list of workflow objects, `%{"workflows" => [...]}`,
  or an object keyed by workflow id. Every imported entry must expose a real id
  and an L0-L3 risk level. Missing facts fail closed.
  """

  alias AgentRuntime.ExternalWorkflowSpec

  @spec import_file(Path.t()) :: {:ok, [ExternalWorkflowSpec.t()]} | {:error, term()}
  def import_file(path) do
    with {:ok, json} <- File.read(path) do
      import_json(json)
    else
      {:error, reason} -> {:error, {:file_read_failed, reason}}
    end
  end

  @spec import_json(binary()) :: {:ok, [ExternalWorkflowSpec.t()]} | {:error, term()}
  def import_json(json) when is_binary(json) do
    with {:ok, decoded} <- Jason.decode(json),
         {:ok, entries} <- normalize_container(decoded),
         {:ok, specs} <- normalize_entries(entries),
         :ok <- validate_unique_ids(specs) do
      {:ok, specs}
    else
      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:invalid_json, Exception.message(error)}}

      {:error, _reason} = error ->
        error
    end
  end

  @spec risk_distribution([ExternalWorkflowSpec.t()]) :: map()
  def risk_distribution(specs) when is_list(specs) do
    base = %{"L0" => 0, "L1" => 0, "L2" => 0, "L3" => 0}

    Enum.reduce(specs, base, fn spec, acc -> Map.update!(acc, spec.risk_level, &(&1 + 1)) end)
  end

  defp normalize_container(%{"workflows" => workflows}) when is_list(workflows),
    do: {:ok, workflows}

  defp normalize_container(workflows) when is_list(workflows), do: {:ok, workflows}

  defp normalize_container(workflows) when is_map(workflows) do
    entries =
      Enum.map(workflows, fn {id, value} ->
        if is_map(value), do: Map.put_new(value, "id", id), else: %{"id" => id, "value" => value}
      end)

    {:ok, entries}
  end

  defp normalize_container(_value), do: {:error, :unsupported_tcc_registry_shape}

  defp normalize_entries(entries) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
      case normalize_entry(entry) do
        {:ok, spec} -> {:cont, {:ok, [spec | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, specs} -> {:ok, Enum.reverse(specs)}
      error -> error
    end
  end

  defp normalize_entry(entry) when is_map(entry) do
    id = first_present(entry, ~w(id workflow_id workflow name))
    risk_level = first_present(entry, ~w(risk_level risk level))
    capability = first_present(entry, ~w(capability router_capability category))
    blocker = first_present(entry, ~w(blocker blocked_reason block_reason))
    status = first_present(entry, ~w(status state))

    attrs = %{
      id: id,
      runtime_set: "shadowmaker_tasks",
      executor: "tcc",
      risk_level: risk_level,
      capability: capability,
      blocker: blocker,
      status: normalize_status(status),
      metadata: %{source: "shadowmaker-tasks/workflows.json", raw: entry}
    }

    case ExternalWorkflowSpec.new(attrs) do
      {:ok, spec} -> {:ok, spec}
      {:error, reason} -> {:error, {:invalid_tcc_workflow, id, reason}}
    end
  end

  defp normalize_entry(_entry), do: {:error, :invalid_tcc_workflow_entry}

  defp first_present(map, keys) do
    Enum.find_value(keys, fn key ->
      case Map.get(map, key) do
        nil -> nil
        "" -> nil
        value -> value
      end
    end)
  end

  defp normalize_status(nil), do: :known
  defp normalize_status(value) when is_binary(value), do: value
  defp normalize_status(value), do: to_string(value)

  defp validate_unique_ids(specs) do
    duplicates =
      specs
      |> Enum.map(& &1.id)
      |> Enum.frequencies()
      |> Enum.filter(fn {_id, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    if duplicates == [], do: :ok, else: {:error, {:duplicate_workflow_ids, duplicates}}
  end
end
