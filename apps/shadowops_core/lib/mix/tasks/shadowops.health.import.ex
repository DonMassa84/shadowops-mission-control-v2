defmodule Mix.Tasks.Shadowops.Health.Import do
  use Mix.Task

  @shortdoc "Imports a sanitized local health manifest into ShadowOps local state"

  alias ShadowOpsCore.Health.DocumentIntake

  @impl Mix.Task
  def run([manifest_path | _rest]) do
    Mix.Task.run("app.start")

    with {:ok, body} <- File.read(manifest_path),
         {:ok, decoded} <- Jason.decode(body),
         {:ok, documents} <- documents(decoded),
         {:ok, events} <- build_events(documents),
         {:ok, store_path} <- persist(events) do
      Mix.shell().info("HEALTH_IMPORT=OK")
      Mix.shell().info("DOCUMENTS=#{length(documents)}")
      Mix.shell().info("EVENTS=#{length(events)}")
      Mix.shell().info("STORE=#{store_path}")
      Mix.shell().info("PRIVACY=LOCAL_ONLY")
    else
      {:error, reason} -> Mix.raise("health import failed: #{inspect(reason)}")
    end
  end

  def run(_args), do: Mix.raise("usage: mix shadowops.health.import PATH_TO_MANIFEST.json")

  defp documents(%{"documents" => documents}) when is_list(documents), do: {:ok, documents}
  defp documents(documents) when is_list(documents), do: {:ok, documents}
  defp documents(_), do: {:error, :documents_must_be_a_list}

  defp build_events(documents) do
    Enum.reduce_while(documents, {:ok, []}, fn document, {:ok, acc} ->
      event_type = Map.get(document, "event_type", "health.document_ingested")

      case DocumentIntake.build_event(document, event_type) do
        {:ok, event} -> {:cont, {:ok, [event | acc]}}
        {:error, reason} -> {:halt, {:error, {Map.get(document, "resource_id"), reason}}}
      end
    end)
    |> case do
      {:ok, events} -> {:ok, Enum.reverse(events)}
      error -> error
    end
  end

  defp persist(events) do
    store_path =
      System.get_env("SHADOWOPS_HEALTH_STORE") ||
        Path.expand("priv/health/events.jsonl", File.cwd!())

    with :ok <- File.mkdir_p(Path.dirname(store_path)),
         payload <- Enum.map_join(events, "", &(Jason.encode!(&1) <> "\n")),
         :ok <- File.write(store_path, payload, [:append]) do
      {:ok, store_path}
    end
  end
end
