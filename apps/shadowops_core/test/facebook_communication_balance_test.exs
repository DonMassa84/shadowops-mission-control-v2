defmodule ShadowOps.Social.FacebookCommunicationBalanceTest do
  use ExUnit.Case, async: true

  alias ShadowOps.Social.FacebookCommunicationBalance, as: Balance

  test "50 percent outbound and initiation with equal follow-ups is balanced" do
    result = classify(outbound: 0.50, initiation: 0.50, followups_me: 3, followups_other: 3)

    assert result["status"] == "BALANCED"
    assert result["direction"] == "BALANCED"
    assert result["active_signals"] == []
    assert "OUTBOUND_BALANCED" in result["reason_codes"]
    assert "INITIATION_BALANCED" in result["reason_codes"]
  end

  test "high initiation alone is watch" do
    result = classify(initiation: 0.70)

    assert result["status"] == "WATCH"
    assert result["active_signals"] == ["INITIATION_HIGH"]
    assert "INITIATION_HIGH" in result["reason_codes"]
  end

  test "high outbound and high initiation is overinvesting" do
    result = classify(outbound: 0.65, initiation: 0.75)

    assert result["status"] == "OVERINVESTING"
    assert result["active_signals"] == ["OUTBOUND_HIGH", "INITIATION_HIGH"]
  end

  test "strong follow-ups and strong initiation is overinvesting" do
    result = classify(initiation: 0.70, followups_me: 8, followups_other: 2)

    assert result["status"] == "OVERINVESTING"
    assert "FOLLOWUP_HIGH" in result["active_signals"]
    assert "INITIATION_HIGH" in result["active_signals"]
  end

  test "fast response time alone is context and never an investment signal" do
    result =
      classify(
        response_me: 1.0,
        response_other: 12_000.0,
        outbound: 0.50,
        initiation: 0.50
      )

    assert result["status"] == "BALANCED"
    assert result["active_signals"] == []
    assert result["response_context"]["investment_signal"] == false
    assert result["response_context"]["median_seconds_me"] == 1.0
  end

  test "fewer than 30 messages is insufficient data" do
    result = classify(messages: 29, sessions: 8, outbound: 0.80, initiation: 0.80)

    assert result["status"] == "INSUFFICIENT_DATA"
    assert result["confidence"] == "LOW"
    assert result["early_signal"] == "EARLY_LOW_CONFIDENCE"
    assert "MESSAGES_BELOW_MINIMUM" in result["reason_codes"]
  end

  test "fewer than five sessions is insufficient data" do
    result = classify(messages: 100, sessions: 4, outbound: 0.80, initiation: 0.80)

    assert result["status"] == "INSUFFICIENT_DATA"
    assert result["confidence"] == "INSUFFICIENT"
    assert result["early_signal"] == "NOT_ACTIVE"
    assert "SESSIONS_BELOW_MINIMUM" in result["reason_codes"]
  end

  test "raw names and raw message text never cross the per-chat output boundary" do
    row =
      base_contact()
      |> Map.put("name", "RAW_NAME_SENTINEL")
      |> Map.put("text", "RAW_MESSAGE_SENTINEL")

    output = Balance.classify(row) |> Jason.encode!()

    refute output =~ "RAW_NAME_SENTINEL"
    refute output =~ "RAW_MESSAGE_SENTINEL"
    refute output =~ ~s("name")
    refute output =~ ~s("text")
  end

  test "source privacy gate rejects raw identity or message fields" do
    for {key, value} <- [{"name", "Private Person"}, {"text", "raw message"}] do
      ranking = ranking([Map.put(base_contact(), key, value)])
      assert {:error, :privacy_gate_failed} = Balance.build(ranking, source_sha256: sha())
    end
  end

  test "repeated runs with the same aggregate input are deterministic" do
    opts = [generated_at: "2026-08-23T20:00:00Z", source_commit: "abc123", source_sha256: sha()]
    input = ranking([base_contact(), base_contact("C_1111111111111111", initiation: 0.70)])

    assert {:ok, first} = Balance.build(input, opts)
    assert {:ok, second} = Balance.build(input, opts)
    assert first == second
    assert Jason.encode!(first) == Jason.encode!(second)
  end

  test "early signal and confidence express session volume only" do
    assert classify(sessions: 5)["early_signal"] == "EARLY_LOW_CONFIDENCE"
    assert classify(sessions: 5)["confidence"] == "LOW"
    assert classify(sessions: 9)["confidence"] == "LOW"
    assert classify(sessions: 10)["early_signal"] == "EARLY_MEDIUM_CONFIDENCE"
    assert classify(sessions: 19)["confidence"] == "MEDIUM"
    assert classify(sessions: 20)["early_signal"] == "ESTABLISHED_HIGH_CONFIDENCE"
    assert classify(sessions: 20)["confidence"] == "HIGH"
  end

  test "mirrored counterpart signals are directional and never overinvesting" do
    result = classify(outbound: 0.30, initiation: 0.25, followups_me: 1, followups_other: 8)

    assert result["status"] == "WATCH"
    assert result["direction"] == "COUNTERPART_MORE"
    refute result["status"] == "OVERINVESTING"

    assert Enum.sort(result["active_signals"]) ==
             Enum.sort(~w(OUTBOUND_OTHER_HIGH INITIATION_OTHER_HIGH FOLLOWUP_OTHER_HIGH))
  end

  test "snapshot contains only pseudonymized per-chat output and global knowledge aggregates" do
    contacts = [base_contact(), base_contact("C_2222222222222222", initiation: 0.70)]

    assert {:ok, result} =
             Balance.build(ranking(contacts),
               generated_at: "2026-08-23T20:00:00Z",
               source_commit: "abc123",
               source_sha256: sha()
             )

    assert result["status"] == "BALANCE_CLASSIFIER_READY"

    assert result["counts"] == %{
             "BALANCED" => 1,
             "WATCH" => 1,
             "OVERINVESTING" => 0,
             "INSUFFICIENT_DATA" => 0
           }

    assert result["knowledge_aggregates"] == %{
             "facebook_balance_balanced_count" => 1,
             "facebook_balance_watch_count" => 1,
             "facebook_balance_overinvesting_count" => 0,
             "facebook_balance_sufficient_data_count" => 2
           }

    encoded = Jason.encode!(result)
    refute encoded =~ "Private Person"
    refute encoded =~ "raw message"
    assert encoded =~ "PSEUDONYMIZED_AGGREGATE"
  end

  test "writes atomically and loads only a valid privacy-safe snapshot" do
    source = fixture(Jason.encode!(ranking([base_contact()])))
    output = fixture_path()

    assert {:ok, result} =
             Balance.build_file(source,
               generated_at: "2026-08-23T20:00:00Z",
               source_commit: "abc123"
             )

    assert :ok = Balance.write_snapshot(result, output)
    assert {:ok, ^result} = Balance.snapshot(output)
    assert {:ok, %{ready?: true, status: "BALANCE_CLASSIFIER_READY"}} = Balance.load(output)
  end

  defp classify(opts) do
    opts
    |> then(&base_contact("C_0123456789abcdef", &1))
    |> Balance.classify()
  end

  defp base_contact(chat \\ "C_0123456789abcdef", opts \\ []) do
    %{
      "chat" => chat,
      "messages" => Keyword.get(opts, :messages, 100),
      "inbound" => 50,
      "outbound" => 50,
      "outbound_share_me" => Keyword.get(opts, :outbound, 0.50),
      "sessions" => Keyword.get(opts, :sessions, 20),
      "initiations_me" => 10,
      "initiations_other" => 10,
      "initiation_share_me" => Keyword.get(opts, :initiation, 0.50),
      "followups_me_ge30m" => Keyword.get(opts, :followups_me, 2),
      "followups_other_ge30m" => Keyword.get(opts, :followups_other, 2),
      "median_response_seconds_me" => Keyword.get(opts, :response_me, 30.0),
      "median_response_seconds_other" => Keyword.get(opts, :response_other, 30.0),
      "p90_response_seconds_me" => 120.0,
      "p90_response_seconds_other" => 120.0,
      "category" => "ausgeglichen"
    }
  end

  defp ranking(contacts) do
    %{
      "status" => "CONTACT_RANKING_READY",
      "total_one_to_one_chats" => length(contacts),
      "categories" => %{},
      "contacts" => contacts,
      "privacy" => %{
        "raw_names" => false,
        "raw_messages" => false,
        "media" => false,
        "chat_ids_pseudonymous" => true
      }
    }
  end

  defp sha, do: String.duplicate("a", 64)

  defp fixture(contents) do
    path = fixture_path()
    File.write!(path, contents)
    path
  end

  defp fixture_path do
    path =
      Path.join(System.tmp_dir!(), "facebook-balance-#{System.unique_integer([:positive])}.json")

    on_exit(fn -> File.rm(path) end)
    path
  end
end
