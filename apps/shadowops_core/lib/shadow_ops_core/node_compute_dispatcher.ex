defmodule ShadowOpsCore.NodeComputeDispatcher do
  @moduledoc """
  Routes bounded compute jobs through the capability router and dispatches them only
  when the selected node has current verified evidence.

  At present the only remote compute executor is the i7 executor. Other selected
  nodes fail closed until an equivalent bounded executor exists.
  """

  alias ShadowOpsCore.{I7Node, I7RemoteExecutor, NodeCapabilityRouter, RuntimeSources}

  @job_capabilities %{
    cpu_probe: "supplementary_compute",
    format: "qa",
    compile: "qa",
    target_test: "qa",
    full_test: "qa",
    qa_bundle: "qa",
    diff_check: "repository_change"
  }

  def dispatch(job, expected_sha, context \\ %{})

  def dispatch(job, expected_sha, context)
      when is_atom(job) and is_binary(expected_sha) and is_map(context) do
    with {:ok, capability} <- capability_for(job),
         nodes <- current_nodes(),
         {:ok, %{node_id: "i7"} = route} <-
           NodeCapabilityRouter.route(capability, nodes, context),
         {:ok, result} <- I7RemoteExecutor.execute(job, expected_sha) do
      {:ok, %{route: route, execution: result}}
    else
      {:ok, %{node_id: other}} -> {:error, {:executor_not_implemented, other}}
      {:error, _reason} = error -> error
    end
  end

  def dispatch(_job, _expected_sha, _context), do: {:error, :invalid_dispatch_request}

  @doc false
  def capability_for(job) do
    case Map.fetch(@job_capabilities, job) do
      {:ok, capability} -> {:ok, capability}
      :error -> {:error, :job_not_allowlisted}
    end
  end

  @doc false
  def current_nodes do
    RuntimeSources.nodes()
    |> Map.get(:records, [])
    |> Enum.reject(&((Map.get(&1, :node_id) || Map.get(&1, "node_id")) == "i7"))
    |> Kernel.++([I7Node.status()])
  end
end
