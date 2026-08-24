defmodule ShadowOpsCore.Adapters.CanonicalWorkflowAdapter do
  @moduledoc """
  Fail-closed bridge from ExecutionService to trusted
  canonical workflow definitions.

  Client input cannot select arbitrary executors,
  commands, runtime paths or adapter modules.
  """

  @behaviour ShadowOpsCore.Adapters.Adapter

  alias ShadowOpsCore.{
    WorkflowManifest,
    WorkflowSource
  }

  alias ShadowOpsCore.Adapters.{
    ScriptAdapter,
    SystemdAdapter
  }

  @executable_statuses [
    "active",
    "VERIFIED_EXECUTABLE"
  ]

  @impl true
  def execute(
        %{executor: :canonical_workflow},
        input,
        context
      )
      when is_map(input) and is_map(context) do
    with {:ok, workflow_id} <-
           workflow_id(input),
         {:ok, registry} <-
           WorkflowSource.load(),
         {:ok, workflow} <-
           registry_workflow(
             registry,
             workflow_id
           ),
         {:ok, manifest} <-
           WorkflowManifest.from_registry(
             workflow_id,
             workflow
           ),
         :ok <-
           executable_status(manifest),
         :ok <-
           risk_gate(
             manifest,
             Map.get(
               context,
               :policy_decision
             )
           ) do
      runtime_input =
        Map.drop(
          input,
          [
            :workflow_id,
            "workflow_id"
          ]
        )

      dispatch(
        manifest,
        workflow,
        runtime_input,
        context
      )
    end
  end

  def execute(_, _, _),
    do: {:error, :invalid_canonical_workflow_request}

  # ----------------------------------------
  # Adapter mapping
  # ----------------------------------------

  @doc false
  def adapter_for(%{source: "local_script"}),
    do: {:ok, ScriptAdapter}

  def adapter_for(%{source: "systemd"}),
    do: {:ok, SystemdAdapter}

  def adapter_for(%{source: "github_actions"}),
    do: {:error, :github_dispatch_not_connected}

  def adapter_for(%{source: source}),
    do: {:error, {:workflow_executor_not_connected, source}}

  # ----------------------------------------
  # Runtime dispatch
  # ----------------------------------------

  defp dispatch(
         %{source: "local_script"} = manifest,
         _workflow,
         input,
         context
       ) do
    with :ok <-
           ScriptAdapter.validate(manifest) do
      ScriptAdapter.run(
        manifest,
        input,
        context
      )
    end
  end

  defp dispatch(
         %{source: "systemd"},
         workflow,
         input,
         context
       ) do
    with {:ok, service} <-
           systemd_resource(workflow),
         :ok <-
           SystemdAdapter.validate(service) do
      case action(input) do
        action
        when action in [
               "start",
               "restart"
             ] ->
          SystemdAdapter.run(
            service,
            %{"action" => action},
            context
          )

        "stop" ->
          SystemdAdapter.stop(
            service,
            context
          )

        _ ->
          {:error, :systemd_action_required}
      end
    end
  end

  defp dispatch(
         %{source: "github_actions"},
         _workflow,
         _input,
         _context
       ),
       do: {:error, :github_dispatch_not_connected}

  defp dispatch(
         %{source: source},
         _workflow,
         _input,
         _context
       ),
       do: {:error, {:workflow_executor_not_connected, source}}

  # ----------------------------------------
  # Risk
  # ----------------------------------------

  @doc false
  def risk_gate(manifest, decision) do
    risk =
      Map.get(
        manifest,
        :risk_level
      )

    case {risk, decision} do
      {"L0", value}
      when value in [
             "AUTO",
             "APPROVED"
           ] ->
        :ok

      {"L1", value}
      when value in [
             "AUTO",
             "APPROVED"
           ] ->
        :ok

      {"L2", "APPROVED"} ->
        :ok

      {"L3", "APPROVED"} ->
        :ok

      {"L2", _} ->
        {:error, {:workflow_approval_required, "L2"}}

      {"L3", _} ->
        {:error, {:workflow_approval_required, "L3"}}

      {nil, _} ->
        {:error, :workflow_risk_missing}

      {risk, _} ->
        {:error, {:invalid_workflow_risk, risk}}
    end
  end

  # ----------------------------------------
  # Registry
  # ----------------------------------------

  defp workflow_id(input) do
    id =
      Map.get(
        input,
        :workflow_id
      ) ||
        Map.get(
          input,
          "workflow_id"
        )

    if is_binary(id) and
         byte_size(id) > 0 do
      {:ok, id}
    else
      {:error, :workflow_id_required}
    end
  end

  defp registry_workflow(
         %{"workflows" => workflows},
         workflow_id
       )
       when is_map(workflows) do
    case Map.fetch(
           workflows,
           workflow_id
         ) do
      {:ok, workflow} ->
        {:ok, workflow}

      :error ->
        {:error, {:unknown_workflow, workflow_id}}
    end
  end

  defp registry_workflow(_, _),
    do: {:error, :invalid_workflow_registry}

  defp executable_status(manifest) do
    metadata =
      Map.get(
        manifest,
        :metadata,
        %{}
      )

    status =
      Map.get(
        metadata,
        :registry_status
      )

    if status in @executable_statuses do
      :ok
    else
      {:error, {:workflow_not_executable, status}}
    end
  end

  # ----------------------------------------
  # systemd
  # ----------------------------------------

  defp systemd_resource(workflow) do
    name =
      Map.get(
        workflow,
        "service_name"
      )

    scope =
      Map.get(
        workflow,
        "scope",
        "user"
      )

    if is_binary(name) and
         name != "" and
         scope in [
           "user"
         ] do
      {:ok,
       %{
         name: name,
         scope: scope
       }}
    else
      {:error, :invalid_systemd_workflow}
    end
  end

  defp action(input) do
    Map.get(
      input,
      :action
    ) ||
      Map.get(
        input,
        "action"
      )
  end
end
