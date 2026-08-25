defmodule ShadowOpsWeb.WorkflowsController do
  use Phoenix.Controller, formats: [:json]

  alias ShadowOpsCore.WorkflowJobs
  alias ShadowOpsApi

  def index(conn, _params) do
    with {:ok, workflows} <- ShadowOpsApi.list_workflows() do
      json(conn, %{
        id: "workflows",
        name: "Workflows",
        kind: "workflow_registry",
        status: "READY",
        health: "HEALTHY",
        source: "workflow_registry_v2.yaml",
        source_type: "CANONICAL_REGISTRY",
        real_data: true,
        synthetic: false,
        enabled: true,
        reachable: true,
        last_sync_at: nil,
        last_success_at: nil,
        latency_ms: nil,
        workflows: workflows,
        record_count: length(workflows),
        error_code: nil,
        error_message: nil,
        metadata: %{}
      })
    end
  end

  def show(conn, %{"id" => id}) do
    case ShadowOpsApi.get_workflow(id) do
      {:ok, workflow} ->
        json(conn, workflow)

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "workflow_not_found", detail: "Workflow #{id} not found"})
    end
  end

  def run(conn, %{"id" => id}) do
    actor = get_actor(conn)
    input = conn.body_params
    context = Map.put(input, :approval_id, input["approval_id"])

    result =
      if WorkflowJobs.enabled?() do
        WorkflowJobs.enqueue_request(id, actor, input, context)
      else
        ShadowOpsApi.execute_workflow(id, actor, input, context)
      end

    case result do
      {:ok, run, job} ->
        conn
        |> put_status(:accepted)
        |> json(%{status: run.status, workflow_id: id, run: run, job: job, persistent: true})

      {:ok, run} ->
        json(conn, %{status: run.status, workflow_id: id, run: run, persistent: false})

      {:error, {:approval_required, run}} ->
        conn |> put_status(:conflict) |> json(%{error: "approval_required", run: run})

      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{error: "execution_failed", reason: inspect(reason)})
    end
  end

  defp get_actor(conn) do
    conn.assigns.actor
  end
end
