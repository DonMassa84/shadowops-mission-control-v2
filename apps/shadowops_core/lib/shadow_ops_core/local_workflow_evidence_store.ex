defmodule ShadowOpsCore.LocalWorkflowEvidenceStore do
  @moduledoc """
  Persistent evidence overlay for locally discovered `localwf_*` records.

  Discovery remains owned by `LocalWorkflowRegistry`. This store cannot create workflow
  identities or execution rights on its own: every write is validated against the current
  discovery registry, source references must match, unknown fields are rejected, and
  corrupt/unreadable evidence fails closed.
  """

  alias ShadowOpsCore.LocalWorkflowRegistry

  @path Path.expand("../../../../var/local_workflow_evidence.json", __DIR__)
  @boolean_fields ~w(runtime_verified real_data reachable execution_tested governance_mapped executable)a
  @string_fields ~w(source_ref adapter capability risk_level approval_ref verified_at verified_by)a
  @list_fields ~w(evidence_refs)a
  @allowed_fields MapSet.new(@boolean_fields ++ @string_fields ++ @list_fields)
  @risk_levels ~w(L0 L1 L2 L3)
  @max_string 512
  @max_evidence_refs 32

  def path, do: Application.get_env(:shadowops_core, :local_workflow_evidence_path, @path)

  @doc "Returns only evidence that still validates against the current discovery registry."
  def snapshot(registry \\ nil) do
    registry = registry || LocalWorkflowRegistry.snapshot()
    records = registry_records(registry)

    case read_store() do
      {:ok, stored} ->
        stored
        |> Enum.reduce(%{}, fn {id, evidence}, acc ->
          case validate_loaded(id, evidence, records) do
            {:ok, normalized} -> Map.put(acc, id, normalized)
            :error -> acc
          end
        end)

      {:error, _reason} ->
        %{}
    end
  end

  @doc "Reads validated evidence for one discovered workflow."
  def get(id, registry \\ nil)

  def get(id, registry) when is_binary(id) do
    case Map.fetch(snapshot(registry), id) do
      {:ok, evidence} -> {:ok, evidence}
      :error -> {:error, :unknown_workflow_id}
    end
  end

  def get(_, _), do: {:error, :invalid_workflow_id}

  @doc "Atomically replaces the evidence overlay for one currently discovered workflow."
  def put(id, attrs, registry \\ nil)

  def put(id, attrs, registry) when is_binary(id) and is_map(attrs) do
    registry = registry || LocalWorkflowRegistry.snapshot()
    records = registry_records(registry)

    transact(fn ->
      with {:ok, record} <- fetch_registry_record(records, id),
           :ok <- validate_attribute_keys(attrs),
           {:ok, evidence} <- normalize_input(record, attrs),
           {:ok, stored} <- read_store_allow_missing(),
           :ok <- write_store(Map.put(stored, id, evidence)) do
        {:ok, evidence}
      end
    end)
  end

  def put(_, _, _), do: {:error, :invalid_evidence}

  defp normalize_input(record, attrs) do
    attrs = atomize_known_keys(attrs)
    source_ref = Map.get(attrs, :source_ref, record.source_ref)

    with true <- source_ref == record.source_ref,
         {:ok, strings} <- normalize_strings(attrs),
         {:ok, refs} <- normalize_evidence_refs(Map.get(attrs, :evidence_refs, [])),
         {:ok, risk} <- normalize_risk(Map.get(attrs, :risk_level, "L3")),
         :ok <- validate_execution_approval(attrs, strings, risk) do
      now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

      {:ok,
       %{
         workflow_id: record.id,
         source_ref: record.source_ref,
         runtime_verified: truthy?(attrs, :runtime_verified),
         real_data: truthy?(attrs, :real_data),
         reachable: truthy?(attrs, :reachable),
         execution_tested: truthy?(attrs, :execution_tested),
         governance_mapped: truthy?(attrs, :governance_mapped),
         executable: truthy?(attrs, :executable),
         adapter: Map.get(strings, :adapter),
         capability: Map.get(strings, :capability),
         risk_level: risk,
         approval_required: risk in ~w(L2 L3),
         approval_ref: Map.get(strings, :approval_ref),
         evidence_refs: refs,
         verified_at: Map.get(strings, :verified_at) || now,
         verified_by: Map.get(strings, :verified_by) || "shadowops"
       }}
    else
      false -> {:error, :source_ref_mismatch}
      error -> error
    end
  end

  defp validate_loaded(id, evidence, records) when is_map(evidence) do
    with {:ok, record} <- fetch_registry_record(records, id),
         true <- value(evidence, :workflow_id) == id,
         true <- value(evidence, :source_ref) == record.source_ref,
         {:ok, normalized} <- normalize_input(record, evidence) do
      {:ok, normalized}
    else
      _ -> :error
    end
  end

  defp validate_loaded(_, _, _), do: :error

  defp validate_attribute_keys(attrs) do
    keys =
      attrs
      |> Map.keys()
      |> Enum.map(&known_key/1)

    cond do
      Enum.any?(keys, &is_nil/1) -> {:error, :unknown_evidence_field}
      Enum.all?(keys, &MapSet.member?(@allowed_fields, &1)) -> :ok
      true -> {:error, :unknown_evidence_field}
    end
  end

  defp normalize_strings(attrs) do
    Enum.reduce_while(@string_fields -- [:source_ref, :risk_level], {:ok, %{}}, fn key,
                                                                                   {:ok, acc} ->
      case Map.get(attrs, key) do
        nil ->
          {:cont, {:ok, acc}}

        value when is_binary(value) and byte_size(value) <= @max_string ->
          {:cont, {:ok, Map.put(acc, key, value)}}

        _ ->
          {:halt, {:error, {:invalid_evidence_field, key}}}
      end
    end)
  end

  defp validate_execution_approval(attrs, strings, risk) do
    executable = truthy?(attrs, :executable)
    approval_ref = Map.get(strings, :approval_ref)

    if executable and risk in ~w(L2 L3) and not nonempty_string?(approval_ref) do
      {:error, :approval_required_for_execution}
    else
      :ok
    end
  end

  defp normalize_evidence_refs(refs) when is_list(refs) and length(refs) <= @max_evidence_refs do
    if Enum.all?(refs, &(is_binary(&1) and byte_size(&1) <= @max_string)) do
      {:ok, refs |> Enum.uniq() |> Enum.sort()}
    else
      {:error, :invalid_evidence_refs}
    end
  end

  defp normalize_evidence_refs(_), do: {:error, :invalid_evidence_refs}

  defp normalize_risk(risk) when risk in @risk_levels, do: {:ok, risk}
  defp normalize_risk(_), do: {:error, :invalid_risk_level}

  defp atomize_known_keys(attrs) do
    Map.new(attrs, fn {key, value} -> {known_key(key) || key, value} end)
  end

  defp known_key(key) when is_atom(key), do: if(MapSet.member?(@allowed_fields, key), do: key)

  defp known_key(key) when is_binary(key) do
    Enum.find(@boolean_fields ++ @string_fields ++ @list_fields, &(Atom.to_string(&1) == key))
  end

  defp known_key(_), do: nil

  defp truthy?(attrs, key), do: Map.get(attrs, key, false) == true
  defp nonempty_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp registry_records(registry) do
    registry
    |> Map.get(:records, [])
    |> Map.new(&{&1.id, &1})
  end

  defp fetch_registry_record(records, "localwf_" <> _ = id) do
    case Map.fetch(records, id) do
      {:ok, record} -> {:ok, record}
      :error -> {:error, :unknown_workflow_id}
    end
  end

  defp fetch_registry_record(_, _), do: {:error, :invalid_workflow_id}

  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp read_store_allow_missing do
    case read_store() do
      {:error, :enoent} -> {:ok, %{}}
      other -> other
    end
  end

  defp read_store do
    case File.read(path()) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
          _ -> {:error, :corrupt_evidence_store}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_store(records) do
    File.mkdir_p!(Path.dirname(path()))
    temp = path() <> ".tmp.#{System.unique_integer([:positive])}"
    body = Jason.encode!(records)

    with :ok <- File.write(temp, body, [:binary, :sync]),
         :ok <- File.rename(temp, path()) do
      :ok
    else
      {:error, reason} ->
        File.rm(temp)
        {:error, reason}
    end
  end

  defp transact(fun), do: :global.trans({{__MODULE__, path()}, self()}, fun)
end
