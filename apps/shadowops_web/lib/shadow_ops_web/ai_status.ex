defmodule ShadowOpsWeb.AIStatus do
  @moduledoc "Fail-closed AI policy projection for Mission Control."

  def snapshot do
    %{
      id: "ai",
      name: "AI Governance",
      kind: "ai_policy",
      availability: "AVAILABLE",
      status: "READY",
      health: "HEALTHY",
      source: "docs/REMOTE_AI_POLICY.md + CapabilityRegistry",
      source_type: "POLICY",
      real_data: true,
      synthetic: false,
      enabled: true,
      reachable: true,
      records: [],
      models: [],
      loaded_models: [],
      count: 0,
      record_count: 0,
      updated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      policy: %{
        coding_execution: "REMOTE_ONLY",
        local_llm_runtime: "DISABLED",
        local_coding_fallback: "FORBIDDEN",
        fallback: "NONE",
        model_authority: "CLI --model"
      }
    }
  end
end
