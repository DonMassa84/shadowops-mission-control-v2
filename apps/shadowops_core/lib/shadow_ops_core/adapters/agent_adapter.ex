defmodule ShadowOpsCore.Adapters.AgentAdapter do
  @moduledoc "Read-through adapter for agents discovered from existing runtime services."
  @behaviour ShadowOpsCore.Adapters.RuntimeAdapter

  alias ShadowOpsCore.{Evidence, RuntimeSources}

  @impl true
  def discover(_opts \\ []), do: {:ok, RuntimeSources.agents().records}
  @impl true
  def status(_opts \\ []) do
    source = RuntimeSources.agents()

    source
    |> Map.take([:status, :health, :record_count, :source])
    |> Map.merge(%{state: "DEGRADED", reason: "agent_execution_not_connected"})
  end

  @impl true
  def validate(%{id: id}) when is_binary(id), do: :ok
  def validate(_), do: {:error, :invalid_agent}
  @impl true
  def run(_, _, _), do: {:error, :agent_execution_not_connected}
  @impl true
  def stop(_, _), do: {:error, :agent_execution_not_connected}
  @impl true
  def health(agent), do: %{status: Map.get(agent, :health, "UNKNOWN")}
  @impl true
  def evidence(%{id: id, status: status}),
    do:
      Evidence.build(
        "agent:" <> id,
        "runtime",
        [
          %{
            gate: "runtime",
            result: if(status == "READY", do: "PASS", else: "FAIL"),
            evidence_ref: "runtime:" <> id
          }
        ],
        "systemd agent discovery"
      )
end
