defmodule ShadowOpsCore.Adapters.SystemdAdapter do
  @moduledoc "Adapter over existing systemd discovery and allowlisted service operations."
  @behaviour ShadowOpsCore.Adapters.RuntimeAdapter

  alias ShadowOpsCore.{Evidence, RuntimeSources}

  @impl true
  def discover(_opts \\ []), do: {:ok, RuntimeSources.services().services}

  @impl true
  def status(_opts \\ []),
    do: Map.take(RuntimeSources.services(), [:status, :health, :record_count, :source])

  @impl true
  def validate(%{name: name, scope: scope}) when is_binary(name) and is_binary(scope), do: :ok
  def validate(_), do: {:error, :invalid_service}

  @impl true
  def run(%{name: name, scope: scope}, %{"action" => action}, %{policy_decision: decision})
      when action in ["start", "restart"] and decision in ["AUTO", "APPROVED"],
      do: RuntimeSources.service_action(scope <> ":" <> name, action)

  def run(_, _, _), do: {:error, :policy_decision_required}

  @impl true
  def stop(%{name: name, scope: scope}, %{policy_decision: decision})
      when decision in ["AUTO", "APPROVED"],
      do: RuntimeSources.service_action(scope <> ":" <> name, "stop")

  def stop(_, _), do: {:error, :policy_decision_required}

  @impl true
  def health(service), do: %{status: Map.get(service, :status, "UNKNOWN")}

  @impl true
  def evidence(%{name: name, active_state: state}) do
    Evidence.build(
      "service:" <> name,
      "systemd",
      [
        %{
          gate: "systemd_active",
          result: if(state == "active", do: "PASS", else: "FAIL"),
          evidence_ref: "systemctl:" <> name
        }
      ],
      "systemctl live probe"
    )
  end
end
