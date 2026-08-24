defmodule ShadowOpsWeb.ReadinessController do
  use Phoenix.Controller, formats: [:json]
  alias WorkflowEngine.Registry
  alias ShadowOpsCore.{LearningFocus, Audit}

  def show(conn, _) do
    registry = match?({:ok, _}, Registry.summary())
    {:ok, learning} = LearningFocus.load()
    audit_chain = match?({:ok, %{valid: true}}, Audit.verify())
    ready = registry and learning["availability"] == "AVAILABLE" and audit_chain

    conn
    |> put_status(if(ready, do: 200, else: 503))
    |> json(%{
      status: if(ready, do: "ready", else: "not_ready"),
      checks: %{
        registry: if(registry, do: "AVAILABLE", else: "UNAVAILABLE"),
        learning_focus: learning["availability"],
        audit_chain: if(audit_chain, do: "VALID", else: "INVALID")
      }
    })
  end
end
