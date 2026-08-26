defmodule WorkflowEngine.WorkflowIds do
  @moduledoc """
  Canonical loader and validator for ShadowOps global workflow identifiers.

  Registry keys remain local workflow keys. Global IDs are immutable references
  from `config/workflow_ids.yaml`; unknown external IDs are never synthesized.
  """

  alias WorkflowEngine.Registry

  @workflow_prefix "so:wf:v1:"
  @set_prefix "so:wfset:v1:"

  def path, do: Application.fetch_env!(:workflow_engine, :workflow_ids_path)

  def load(path \\ path()) do
    try do
      data = YamlElixir.read_from_file!(path)

      case validate(data) do
        :ok -> {:ok, data}
        {:error, _reason} = error -> error
      end
    rescue
      exception -> {:error, {:workflow_ids_load_failed, Exception.message(exception)}}
    end
  end

  def all(path \\ path()) do
    with {:ok, data} <- load(path) do
      canonical = entries(data["canonical_workflows"], "canonical")
      federation = entries(data["federation_workflows"], "federation")
      {:ok, canonical ++ federation}
    end
  end

  def get(reference, path \\ path()) when is_binary(reference) do
    with {:ok, workflows} <- all(path) do
      case Enum.find(workflows, &(&1.key == reference or &1.id == reference)) do
        nil -> {:error, :not_found}
        workflow -> {:ok, workflow}
      end
    end
  end

  def canonical_id(local_key, path \\ path()) when is_binary(local_key) do
    with {:ok, data} <- load(path),
         %{"id" => id} <- get_in(data, ["canonical_workflows", local_key]) do
      {:ok, id}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def external_set(set_key, path \\ path()) when is_binary(set_key) do
    with {:ok, data} <- load(path),
         %{} = set <- get_in(data, ["external_runtime_sets", set_key]) do
      {:ok, Map.put(set, "key", set_key)}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def valid?(id) when is_binary(id) do
    String.starts_with?(id, @workflow_prefix) or String.starts_with?(id, @set_prefix)
  end

  def valid?(_), do: false

  def validate!(path \\ path()) do
    case load(path) do
      {:ok, data} -> data
      {:error, reason} -> raise ArgumentError, "invalid workflow IDs: #{inspect(reason)}"
    end
  end

  defp validate(data) when is_map(data) do
    with :ok <- require_map(data, "canonical_workflows"),
         :ok <- require_map(data, "federation_workflows"),
         :ok <- require_map(data, "external_runtime_sets"),
         :ok <- validate_workflow_entries(data),
         :ok <- validate_external_sets(data),
         :ok <- validate_unique_ids(data),
         :ok <- validate_registry_coverage(data) do
      :ok
    end
  end

  defp validate(_), do: {:error, :workflow_ids_must_be_map}

  defp require_map(data, key) do
    if is_map(data[key]), do: :ok, else: {:error, {:invalid_collection, key}}
  end

  defp validate_workflow_entries(data) do
    [data["canonical_workflows"], data["federation_workflows"]]
    |> Enum.flat_map(&Map.to_list/1)
    |> Enum.reduce_while(:ok, fn {key, entry}, :ok ->
      case entry do
        %{"id" => id} when is_binary(key) and is_binary(id) ->
          if String.starts_with?(id, @workflow_prefix),
            do: {:cont, :ok},
            else: {:halt, {:error, {:invalid_workflow_id, key, id}}}

        _ ->
          {:halt, {:error, {:invalid_workflow_entry, key}}}
      end
    end)
  end

  defp validate_external_sets(data) do
    Enum.reduce_while(data["external_runtime_sets"], :ok, fn {key, entry}, :ok ->
      case entry do
        %{"set_id" => id} when is_binary(key) and is_binary(id) ->
          if String.starts_with?(id, @set_prefix),
            do: {:cont, :ok},
            else: {:halt, {:error, {:invalid_workflow_set_id, key, id}}}

        _ ->
          {:halt, {:error, {:invalid_external_set, key}}}
      end
    end)
  end

  defp validate_unique_ids(data) do
    ids =
      Enum.map(data["canonical_workflows"], fn {_key, entry} -> entry["id"] end) ++
        Enum.map(data["federation_workflows"], fn {_key, entry} -> entry["id"] end) ++
        Enum.map(data["external_runtime_sets"], fn {_key, entry} -> entry["set_id"] end)

    if length(ids) == length(Enum.uniq(ids)), do: :ok, else: {:error, :duplicate_workflow_ids}
  end

  defp validate_registry_coverage(data) do
    expected = data["canonical_workflows"] |> Map.keys() |> Enum.sort()

    case Registry.list_workflows() do
      {:error, reason} ->
        {:error, {:registry_unavailable, reason}}

      registry_keys when is_list(registry_keys) ->
        if registry_keys == expected,
          do: :ok,
          else: {:error, {:registry_coverage_mismatch, expected, registry_keys}}
    end
  end

  defp entries(collection, kind) do
    collection
    |> Enum.map(fn {key, entry} ->
      %{
        key: key,
        id: entry["id"],
        domain: entry["domain"],
        kind: kind
      }
    end)
    |> Enum.sort_by(& &1.id)
  end
end
