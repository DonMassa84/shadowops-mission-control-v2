defmodule Mix.Tasks.Shadowops.Registry do
  use Mix.Task

  alias WorkflowEngine.{AgentContract, Registry}
  alias WorkflowEngine.Registry.Error

  @shortdoc "Validate, list, or summarize the ShadowOps workflow registry"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, commands, invalid} = OptionParser.parse(args, strict: [path: :string])

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    path = Keyword.get(opts, :path, Registry.path())

    case commands do
      [] -> validate(path)
      ["validate"] -> validate(path)
      ["list"] -> list(path)
      ["summary"] -> summary(path)
      _ -> Mix.raise("usage: mix shadowops.registry [validate|list|summary] [--path PATH]")
    end
  end

  defp validate(path) do
    with {:ok, registry} <- Registry.load(path),
         :ok <- AgentContract.validate_registry(registry) do
      Mix.shell().info(
        "registry valid: #{registry["registry_name"]} (schema v#{registry["schema_version"]})"
      )

      Mix.shell().info("generic_agent_contract=PASS")
      Mix.shell().info("agent_contract_workflows=#{map_size(registry["workflows"])}")
    else
      {:error, %Error{} = error} -> fail(error)
    end
  end

  defp list(path) do
    case Registry.list_workflows(path) do
      workflows when is_list(workflows) ->
        Enum.each(workflows, fn workflow -> Mix.shell().info(workflow) end)

      {:error, %Error{} = error} ->
        fail(error)
    end
  end

  defp summary(path) do
    case Registry.summary(path) do
      {:ok, data} ->
        Mix.shell().info("registry_name=#{data.registry_name}")
        Mix.shell().info("schema_version=#{data.schema_version}")
        Mix.shell().info("workflows=#{data.workflows}")
        Mix.shell().info("workflow_runs=#{data.workflow_runs}")
        Mix.shell().info("external_runtime_sets=#{data.external_runtime_sets}")

      {:error, %Error{} = error} ->
        fail(error)
    end
  end

  defp fail(%Error{} = error), do: Mix.raise(Error.format(error))
end
