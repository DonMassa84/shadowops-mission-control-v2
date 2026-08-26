defmodule ShadowOpsWeb.OneClick do
  @moduledoc """
  Local Mission Control one-click execution facade.

  A click is the operator decision. When policy requires approval, this module creates and
  approves a durable approval record before invoking the existing governed execution path.
  No adapter is called directly and unavailable capabilities still fail closed.
  """

  alias ShadowOpsCore.{ApprovalStore, ExecutionService, ExecutionTracker, Policy, WorkflowJobs}
  alias ShadowOpsWeb.Plugs.Security

  @default_actor "local-operator"

  def enabled?, do: Application.get_env(:shadowops_web, :one_click_enabled, false) == true

  def actor,
    do: Application.get_env(:shadowops_web, :one_click_actor, @default_actor)

  def available? do
    enabled?() and
      is_binary(Application.get_env(:shadowops_web, :write_token)) and
      Application.get_env(:shadowops_web, :write_token) != ""
  end

  def execute_workflow(workflow_id, action \\ nil) when is_binary(workflow_id) do
    with {:ok, actor} <- authorize_operator(),
         {:ok, context} <- approval_context("workflow.execute", workflow_id, actor) do
      input = %{"trigger" => "mission_control_one_click"}

      input =
        if is_binary(action) and action != "", do: Map.put(input, "action", action), else: input

      result =
        if WorkflowJobs.enabled?() do
          WorkflowJobs.enqueue_request(workflow_id, actor, input, context)
        else
          ExecutionTracker.execute_workflow(workflow_id, actor, input, context)
        end

      normalize_workflow_result(result)
    end
  end

  def execute_service(action, service_id)
      when action in ["start", "restart", "stop"] and is_binary(service_id) do
    capability = "service.#{action}"

    with {:ok, actor} <- authorize_operator(),
         {:ok, context} <- approval_context(capability, service_id, actor) do
      ExecutionTracker.execute_service(
        action,
        actor,
        service_id,
        Map.put(context, :trigger, "mission_control_one_click")
      )
    end
  end

  def execute_service(_action, _service_id), do: {:error, :invalid_service_action}

  def execute_node(action, node_id) when is_binary(action) and is_binary(node_id) do
    capability = "node.#{action}"

    with {:ok, actor} <- authorize_operator(),
         {:ok, context} <- approval_context(capability, node_id, actor) do
      ExecutionService.execute(
        capability,
        actor,
        node_id,
        %{node_id: node_id, action: action},
        context
      )
    end
  end

  def decide_approval(id, decision) when decision in ["approve", "reject"] and is_binary(id) do
    with {:ok, actor} <- authorize_operator() do
      case decision do
        "approve" -> ApprovalStore.approve(id, actor)
        "reject" -> ApprovalStore.reject(id, actor)
      end
    end
  end

  def decide_approval(_id, _decision), do: {:error, :invalid_approval_decision}

  defp authorize_operator do
    token = Application.get_env(:shadowops_web, :write_token)
    actor = actor()

    cond do
      not enabled?() ->
        {:error, :one_click_disabled}

      not is_binary(token) or token == "" ->
        {:error, :writes_disabled}

      true ->
        case Security.authorize_live_write(actor, token) do
          :ok -> {:ok, actor}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp approval_context(capability, resource, actor) do
    with {:ok, policy} <- Policy.evaluate(capability, actor, %{}) do
      if policy.approval_required do
        create_operator_approval(capability, resource, actor, policy.risk_level)
      else
        {:ok, %{trigger: "mission_control_one_click"}}
      end
    end
  end

  defp create_operator_approval(capability, resource, actor, risk) do
    with {:ok, approval} <-
           ApprovalStore.create(%{
             requested_by: actor,
             action: capability,
             resource: resource,
             reason: "Explicit one-click operator approval from Mission Control",
             risk: risk
           }),
         {:ok, approved} <- ApprovalStore.approve(approval.id, actor) do
      {:ok,
       %{
         approval_id: approved.id,
         trigger: "mission_control_one_click",
         one_click: true
       }}
    end
  end

  defp normalize_workflow_result({:ok, run, _job}), do: {:ok, run}
  defp normalize_workflow_result({:ok, run}), do: {:ok, run}
  defp normalize_workflow_result({:error, reason}), do: {:error, reason}
end
