defmodule AgentRuntime.ExternalWorkflowCatalog do
  @moduledoc """
  Builds normalized external workflow specs from the schema-v2 registry.

  The current registry names all 16 WhatsApp workflows individually while the
  remaining shadowmaker-tasks workflows are represented only by aggregate
  counts. Those unresolved entries are reported explicitly rather than being
  fabricated.
  """

  alias AgentRuntime.ExternalWorkflowSpec
  alias WorkflowEngine.Registry

  @levels ~w(L0 L1 L2)

  @spec load() :: {:ok, [ExternalWorkflowSpec.t()]} | {:error, term()}
  def load do
    with {:ok, registry} <- Registry.load() do
      from_registry(registry)
    end
  end

  @spec from_registry(map()) :: {:ok, [ExternalWorkflowSpec.t()]} | {:error, term()}
  def from_registry(registry) when is_map(registry) do
    pack = get_in(registry, ["external_runtime_sets", "whatsapp_agent_pack"])

    with true <- is_map(pack),
         groups when is_map(groups) <- pack["risk_groups"] do
      groups
      |> known_whatsapp_entries()
      |> build_specs()
    else
      _ -> {:error, :whatsapp_agent_pack_missing}
    end
  end

  @spec summary(map()) :: {:ok, map()} | {:error, term()}
  def summary(registry) when is_map(registry) do
    with {:ok, known} <- from_registry(registry) do
      expected =
        get_in(registry, ["external_runtime_sets", "shadowmaker_tasks", "total_workflow_count"]) ||
          0

      {:ok,
       %{
         expected_shadowmaker_tasks: expected,
         known_individual_specs: length(known),
         unresolved_shadowmaker_tasks: max(expected - length(known), 0),
         known_ids: Enum.map(known, & &1.id)
       }}
    end
  end

  defp known_whatsapp_entries(groups) do
    Enum.flat_map(@levels, fn level ->
      group = groups[level]
      capability = group["capability"]

      Enum.map(group["workflows"], fn id ->
        %{
          id: id,
          runtime_set: "shadowmaker_tasks",
          executor: "tcc",
          risk_level: level,
          capability: capability,
          metadata: %{domain_pack: "whatsapp_agent_pack"}
        }
      end)
    end)
  end

  defp build_specs(entries) do
    Enum.reduce_while(entries, {:ok, []}, fn attrs, {:ok, acc} ->
      case ExternalWorkflowSpec.new(attrs) do
        {:ok, spec} -> {:cont, {:ok, [spec | acc]}}
        {:error, reason} -> {:halt, {:error, {attrs.id, reason}}}
      end
    end)
    |> case do
      {:ok, specs} -> {:ok, Enum.reverse(specs)}
      error -> error
    end
  end
end
