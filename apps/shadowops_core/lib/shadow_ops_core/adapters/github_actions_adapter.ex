defmodule ShadowOpsCore.Adapters.GitHubActionsAdapter do
  @moduledoc "Discovery adapter for GitHub Actions definitions already referenced by the registry."
  @behaviour ShadowOpsCore.Adapters.RuntimeAdapter

  alias ShadowOpsCore.{Evidence, WorkflowManifest, WorkflowSource}

  @impl true
  def discover(_opts \\ []) do
    with {:ok, registry} <- WorkflowSource.load() do
      rows =
        registry["workflows"]
        |> Enum.flat_map(fn {id, workflow} ->
          case WorkflowManifest.from_registry(id, workflow) do
            {:ok, %{source: "github_actions"} = manifest} ->
              [
                Map.put(
                  manifest,
                  :metadata,
                  Map.put(manifest.metadata, :definition, workflow["definition"])
                )
              ]

            _ ->
              []
          end
        end)

      {:ok, rows}
    end
  end

  @impl true
  def status(opts \\ []) do
    case discover(opts) do
      {:ok, rows} ->
        %{
          state: "DEGRADED",
          discovered: length(rows),
          definitions_valid: Enum.count(rows, &(validate(&1) == :ok)),
          reason: "github_dispatch_not_connected"
        }

      {:error, reason} ->
        %{state: "UNAVAILABLE", discovered: 0, reason: inspect(reason)}
    end
  end

  @impl true
  def validate(%WorkflowManifest{metadata: %{definition: definition}})
      when is_binary(definition) do
    root = Path.expand("../../../../../..", __DIR__)

    if File.regular?(Path.join(root, definition)),
      do: :ok,
      else: {:error, :definition_unavailable}
  end

  def validate(_), do: {:error, :invalid_manifest}
  @impl true
  def run(_, _, _), do: {:error, :github_dispatch_not_connected}
  @impl true
  def stop(_, _), do: {:error, :github_dispatch_not_connected}
  @impl true
  def health(manifest), do: %{status: if(validate(manifest) == :ok, do: "PASS", else: "FAIL")}
  @impl true
  def evidence(%WorkflowManifest{id: id, metadata: %{definition: definition}} = manifest),
    do:
      Evidence.build(
        "workflow:" <> id,
        "github_actions",
        [
          %{
            gate: "definition",
            result: if(validate(manifest) == :ok, do: "PASS", else: "FAIL"),
            evidence_ref: definition
          },
          %{
            gate: "dispatch",
            result: "FAIL",
            evidence_ref: "github_dispatch_not_connected"
          }
        ],
        "canonical workflow registry plus repository file"
      )
end
