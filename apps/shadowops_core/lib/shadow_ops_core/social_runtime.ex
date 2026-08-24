defmodule ShadowOpsCore.SocialRuntime do
  @moduledoc "Overlays verified local social runtime evidence onto canonical connector state."

  alias ShadowOps.Social.FacebookRuntime

  def overlay(%{records: records} = social) when is_list(records) do
    {:ok, runtime} = FacebookRuntime.load()

    if runtime.ready? do
      updated = Enum.map(records, &overlay_facebook(&1, runtime))
      Map.put(social, :records, updated)
    else
      social
    end
  end

  def overlay(social), do: social

  defp overlay_facebook(%{id: "facebook"} = record, runtime) do
    metadata =
      Map.merge(Map.get(record, :metadata, %{}), %{
        classification: "REAL_AGGREGATE_RUNTIME",
        pipeline_status: runtime.pipeline_status,
        ranking_status: runtime.ranking_status,
        privacy_status: runtime.privacy_status,
        total_chats: runtime.metrics["TOTAL CHATS"],
        one_to_one_chats: runtime.metrics["1:1 CHATS"],
        runtime_sha256: runtime.source.sha256,
        source_commit: runtime.source_commit
      })

    Map.merge(record, %{
      status: "READY",
      health: "HEALTHY",
      availability: "AVAILABLE",
      source: runtime.source.path,
      source_type: "LOCAL_AGGREGATE_RUNTIME",
      real_data: true,
      synthetic: false,
      enabled: true,
      reachable: true,
      last_sync_at: runtime.generated_at,
      last_success_at: runtime.generated_at,
      record_count: runtime.metrics["TOTAL MESSAGES"],
      error_code: nil,
      error_message: nil,
      metadata: metadata
    })
  end

  defp overlay_facebook(record, _runtime), do: record
end
