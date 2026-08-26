defmodule Mix.Tasks.Shadowops.External do
  @moduledoc false

  use Mix.Task

  @shortdoc "Inspect or import external ShadowOps workflows"

  alias AgentRuntime.ExternalWorkflowCatalog
  alias AgentRuntime.TccImporter
  alias WorkflowEngine.Registry

  @impl Mix.Task
  def run(["summary"]) do
    Mix.Task.run("app.start")

    with {:ok, registry} <- Registry.load(),
         {:ok, summary} <- ExternalWorkflowCatalog.summary(registry) do
      IO.puts("expected_shadowmaker_tasks=#{summary.expected_shadowmaker_tasks}")
      IO.puts("known_individual_specs=#{summary.known_individual_specs}")
      IO.puts("unresolved_shadowmaker_tasks=#{summary.unresolved_shadowmaker_tasks}")
    else
      {:error, reason} -> Mix.raise("external workflow summary failed: #{inspect(reason)}")
    end
  end

  def run(["list-known"]) do
    Mix.Task.run("app.start")

    case ExternalWorkflowCatalog.load() do
      {:ok, specs} ->
        Enum.each(specs, fn spec ->
          IO.puts("#{spec.id}\t#{spec.risk_level}\t#{spec.capability}\t#{spec.executor}")
        end)

      {:error, reason} ->
        Mix.raise("external workflow catalog failed: #{inspect(reason)}")
    end
  end

  def run(["import", path]) do
    Mix.Task.run("app.start")

    case TccImporter.import_file(path) do
      {:ok, specs} ->
        distribution = TccImporter.risk_distribution(specs)
        IO.puts("imported=#{length(specs)}")
        IO.puts("L0=#{distribution["L0"]}")
        IO.puts("L1=#{distribution["L1"]}")
        IO.puts("L2=#{distribution["L2"]}")
        IO.puts("L3=#{distribution["L3"]}")

      {:error, reason} ->
        Mix.raise("TCC import failed: #{inspect(reason)}")
    end
  end

  def run(_args) do
    Mix.raise("usage: mix shadowops.external summary | list-known | import PATH")
  end
end
