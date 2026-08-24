defmodule ShadowOpsCore.SocialRuntimeTest do
  use ExUnit.Case, async: false

  alias ShadowOpsCore.SocialRuntime

  @runtime Jason.encode!(%{
             "status" => "FACEBOOK_RUNTIME_READY",
             "generated_at" => "2026-08-23T18:00:00Z",
             "source_commit" => "abc123",
             "metrics_status" => "FACEBOOK_METRICS_READY",
             "ranking_status" => "CONTACT_RANKING_READY",
             "all_chats" => %{"messages" => 77_273, "chats" => 723},
             "one_to_one" => %{
               "messages" => 76_112,
               "chats" => 584,
               "inbound" => 37_069,
               "outbound" => 39_043,
               "reciprocity_balance" => 0.9741,
               "initiation_share_me" => 0.5455,
               "median_response_seconds_me" => 27.41,
               "median_response_seconds_other" => 33.36,
               "followups_without_direction_change_ge30m_me" => 313,
               "followups_without_direction_change_ge30m_other" => 205
             },
             "yearly_one_to_one" => [],
             "total_one_to_one_chats" => 584,
             "categories" => %{"ausgeglichen" => 123},
             "privacy" => %{
               "aggregate_only" => true,
               "raw_messages" => false,
               "raw_names" => false,
               "media" => false,
               "contact_records" => false
             }
           })

  setup do
    previous = Application.get_env(:shadowops_core, :facebook_runtime_source)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:shadowops_core, :facebook_runtime_source, previous),
        else: Application.delete_env(:shadowops_core, :facebook_runtime_source)
    end)

    :ok
  end

  test "verified runtime upgrades only Facebook to READY" do
    path = fixture(@runtime)
    Application.put_env(:shadowops_core, :facebook_runtime_source, path)

    social = %{
      records: [
        %{
          id: "facebook",
          status: "DEGRADED",
          health: "DEGRADED",
          availability: "AVAILABLE",
          source: "reconstruction.json",
          source_type: "ANALYTICS_ONLY",
          real_data: true,
          synthetic: false,
          enabled: true,
          reachable: true,
          last_sync_at: nil,
          last_success_at: nil,
          record_count: nil,
          error_code: "ANALYTICS_ONLY",
          error_message: "Aggregate analytics source is not a live connector",
          metadata: %{classification: "ANALYTICS_ONLY"}
        },
        %{id: "telegram", status: "ONLINE"}
      ]
    }

    result = SocialRuntime.overlay(social)
    facebook = Enum.find(result.records, &(&1.id == "facebook"))
    telegram = Enum.find(result.records, &(&1.id == "telegram"))

    assert facebook.status == "READY"
    assert facebook.health == "HEALTHY"
    assert facebook.real_data
    refute facebook.synthetic
    assert facebook.record_count == 77_273
    assert facebook.metadata.one_to_one_chats == 584
    assert facebook.error_code == nil
    assert telegram == %{id: "telegram", status: "ONLINE"}
  end

  test "missing runtime preserves fail-closed connector state" do
    missing = Path.join(System.tmp_dir!(), "facebook-overlay-missing-#{unique()}.json")
    Application.put_env(:shadowops_core, :facebook_runtime_source, missing)

    social = %{records: [%{id: "facebook", status: "DEGRADED", real_data: true}]}
    assert SocialRuntime.overlay(social) == social
  end

  defp fixture(contents) do
    path = Path.join(System.tmp_dir!(), "facebook-overlay-#{unique()}.json")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp unique, do: System.unique_integer([:positive])
end
