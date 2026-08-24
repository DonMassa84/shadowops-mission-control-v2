defmodule ShadowOps.Social.FacebookAnalyticsTest do
  use ExUnit.Case, async: false

  alias ShadowOps.Social.FacebookAnalytics
  alias ShadowOps.Social.FacebookAnalytics.PrivacyGuard

  @valid """
  {"generated_at":"2026-08-20T21:08:56+02:00","privacy":"aggregate-only","evidence":[{"path":"~/fb_forensics/persona_manager.py","sha256":"abc","priority":true,"dimensions":["score_weight"],"matches":[{"line":39,"text":"power_score = interactions / 1000"},{"line":40,"text":"risk_score = interactions / 1000 * 2"}],"identity_map":{}}],"buckets":[{"path":"~/fb_forensics/persona_manager.py","sha256":"def","priority":true,"chain":[{"line":41,"condition":"interactions > 1000","class":"HIGH"},{"line":48,"condition":"else","class":"MANAGEABLE"}]}],"dimension_status":{"volume":{"status":"VERIFIED"},"initiation":{"status":"MISSING"},"reply_response":{"status":"MISSING"},"latency":{"status":"MISSING"},"follow_up":{"status":"PARTIAL"},"reciprocity":{"status":"MISSING"},"balance":{"status":"MISSING"},"score_weight":{"status":"VERIFIED"},"threshold_class":{"status":"VERIFIED"},"ranking":{"status":"VERIFIED"}}}
  """

  test "loads valid aggregate JSON, verified evidence, and no fabricated KPIs" do
    path = fixture(@valid)
    assert {:ok, analytics} = FacebookAnalytics.load(path)
    assert analytics.available?
    assert analytics.json_valid
    assert analytics.data_quality == "PARTIAL"
    assert analytics.evidence_count == 1
    assert analytics.bucket_count == 1
    assert Enum.map(analytics.formulas, & &1.name) == ["power_score", "risk_score"]
    assert [%{condition: "interactions > 1000"} | _] = analytics.thresholds
    assert Enum.all?(analytics.metrics, fn {_key, value} -> is_nil(value) end)
    assert analytics.contact_distribution == []
    refute analytics.contact_distribution_available
    refute analytics.history_available
  end

  test "configuration precedence is Application env, process env, then local default" do
    previous_app = Application.get_env(:shadowops_core, :facebook_analytics_source)
    previous_env = System.get_env("SHADOWOPS_FACEBOOK_ANALYTICS_SOURCE")
    env_path = fixture(@valid)
    app_path = fixture(@valid)

    on_exit(fn ->
      restore_app(previous_app)
      restore_env(previous_env)
    end)

    Application.delete_env(:shadowops_core, :facebook_analytics_source)
    System.put_env("SHADOWOPS_FACEBOOK_ANALYTICS_SOURCE", env_path)
    assert FacebookAnalytics.source_path() == env_path

    Application.put_env(:shadowops_core, :facebook_analytics_source, app_path)
    assert FacebookAnalytics.source_path() == app_path
  end

  test "negative file and JSON paths return a safe unavailable contract" do
    cases = [
      {"empty", ""},
      {"invalid", "not json"},
      {"array", "[]"},
      {"bom", <<0xEF, 0xBB, 0xBF>> <> @valid},
      {"missing-evidence", ~s({"buckets":[],"dimension_status":{}})},
      {"malformed-dimension-status", ~s({"evidence":[],"buckets":[],"dimension_status":[]})},
      {"truncated", ~s({"evidence": [)}
    ]

    Enum.each(cases, fn {_name, contents} ->
      assert_safe_unavailable(FacebookAnalytics.load(fixture(contents)))
    end)

    assert_safe_unavailable(FacebookAnalytics.load(missing_path()))
  end

  test "directory and unreadable sources never crash or expose contents" do
    directory = Path.join(System.tmp_dir!(), "facebook-directory-#{unique()}")
    File.mkdir!(directory)
    on_exit(fn -> File.rmdir(directory) end)
    assert_safe_unavailable(FacebookAnalytics.load(directory))

    unreadable = fixture(@valid)
    File.chmod!(unreadable, 0o000)
    on_exit(fn -> File.chmod(unreadable, 0o600) end)

    case File.read(unreadable) do
      {:error, :eacces} -> assert_safe_unavailable(FacebookAnalytics.load(unreadable))
      {:ok, _body} -> assert {:ok, %{available?: true}} = FacebookAnalytics.load(unreadable)
    end
  end

  test "malformed contact distribution remains unavailable without invalidating real evidence" do
    data = @valid |> Jason.decode!() |> Map.put("contact_distribution", %{"unexpected" => true})
    path = fixture(Jason.encode!(data))

    assert {:ok, %{available?: true, contact_distribution_available: false}} =
             FacebookAnalytics.load(path)

    review = FacebookAnalytics.social_review(path)
    assert review.contact_distribution.status == "UNAVAILABLE"
    assert review.evidence_quality.contact_distribution_available == false
  end

  test "social review exposes only real evidence quality and dimension status" do
    review = FacebookAnalytics.social_review(fixture(@valid))

    assert review.source_status == %{
             status: "AVAILABLE",
             generated_at: "2026-08-20T21:08:56+02:00",
             privacy_status: "PROTECTED",
             data_quality: "PARTIAL"
           }

    assert review.evidence_quality == %{
             source_available: true,
             json_valid: true,
             generated_at_present: true,
             evidence_count: 1,
             bucket_count: 1,
             dimension_verified_count: 4,
             dimension_partial_count: 1,
             dimension_missing_count: 5,
             contact_distribution_available: false
           }

    assert review.reciprocity.status == "UNAVAILABLE"
    assert review.initiation.status == "UNAVAILABLE"
    assert review.response.status == "UNAVAILABLE"
    assert review.latency.status == "UNAVAILABLE"
    assert review.follow_up.status == "PARTIAL"
    assert review.consistency.status == "UNAVAILABLE"
    assert review.balance.status == "UNAVAILABLE"
    assert review.trend.status == "UNAVAILABLE"
    assert review.weekly_social_review == %{status: "UNAVAILABLE", active?: false}
  end

  test "missing source never turns missing metrics into numeric zeroes" do
    review = FacebookAnalytics.social_review(missing_path())
    assert review.source_status.status == "UNAVAILABLE"
    assert review.source_status.privacy_status == "PROTECTED"
    assert review.evidence_quality.evidence_count == nil
    assert review.evidence_quality.bucket_count == nil

    for dimension <-
          ~w(reciprocity initiation response latency follow_up consistency balance trend)a do
      assert Map.fetch!(review, dimension) == %{status: "UNAVAILABLE"}
    end
  end

  test "an empty but valid aggregate contract remains partial rather than verified" do
    assert {:ok, analytics} =
             FacebookAnalytics.load(
               fixture(~s({"evidence":[],"dimension_status":{},"buckets":[]}))
             )

    assert analytics.available?
    assert analytics.data_quality == "PARTIAL"
    assert analytics.evidence_count == 0
    assert analytics.bucket_count == 0
  end

  test "supported and unsupported capabilities remain explicitly separated" do
    review = FacebookAnalytics.social_review(fixture(@valid))

    assert review.capabilities.supported_now ==
             ~w(SOURCE_STATUS EVIDENCE_QUALITY AGGREGATE_RANKING_EVIDENCE DIMENSION_STATUS THRESHOLD_EVIDENCE FORMULA_EVIDENCE)

    assert review.capabilities.unsupported_now ==
             ~w(RECIPROCITY_RATIO INITIATION_BALANCE RESPONSE_RATE RESPONSE_LATENCY FOLLOW_UP_RATIO CONSISTENCY DORMANT_CONTACTS REENGAGED_CONTACTS ONE_SIDED_CONTACTS CONTACT_RANKING HISTORICAL_TRENDS FULL_SOCIAL_HEALTH_SCORE)
  end

  test "privacy guard removes private keys and redacts private-shaped values recursively" do
    private = %{
      "message" => "RAW_MESSAGE_SENTINEL",
      "messages" => ["RAW_MESSAGES_SENTINEL"],
      "text" => "RAW_TEXT_SENTINEL",
      "name" => "RAW_NAME_SENTINEL",
      "first_name" => "RAW_FIRST_NAME_SENTINEL",
      "last_name" => "RAW_LAST_NAME_SENTINEL",
      "phone" => "RAW_PHONE_SENTINEL",
      "email" => "RAW_EMAIL_SENTINEL",
      "media" => "RAW_MEDIA_SENTINEL",
      "cookie" => "RAW_COOKIE_SENTINEL",
      "session" => "RAW_SESSION_SENTINEL",
      "token" => "RAW_TOKEN_SENTINEL",
      "password" => "RAW_PASSWORD_SENTINEL",
      "credential" => "RAW_CREDENTIAL_SENTINEL",
      "identity" => "RAW_IDENTITY_SENTINEL",
      "identity_map" => %{"private" => true},
      "profile" => "RAW_PROFILE_SENTINEL",
      "safe" => %{"status" => "PARTIAL", "value" => "person@example.invalid"}
    }

    sanitized = PrivacyGuard.sanitize(private)
    assert sanitized["safe"]["status"] == "PARTIAL"
    assert sanitized["safe"]["value"] == "[REDACTED]"

    rendered = inspect(sanitized)
    refute rendered =~ "RAW_"
    refute rendered =~ "example.invalid"
  end

  test "signals expose NOT_FOUND and multidimensional formula is not invented" do
    {:ok, analytics} = FacebookAnalytics.load(fixture(@valid))
    assert analytics.signals["Initiation"].status == "NOT_FOUND"
    assert analytics.signals["Follow-ups"].status == "PARTIAL"
    assert analytics.multidimensional_status == "NOT_VERIFIED"
  end

  defp assert_safe_unavailable({:ok, analytics}) do
    refute analytics.available?
    assert analytics.generated_at == nil
    assert analytics.privacy_status == "PROTECTED"
    assert analytics.pipeline_status == "NOT_AVAILABLE"
    assert analytics.ranking_engine_status == "NOT_AVAILABLE"
    assert analytics.evidence == []
    assert analytics.contact_distribution == []
    assert Enum.all?(analytics.metrics, fn {_key, value} -> is_nil(value) end)
  end

  defp fixture(contents) do
    path = Path.join(System.tmp_dir!(), "facebook-analytics-#{unique()}.json")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp missing_path,
    do: Path.join(System.tmp_dir!(), "facebook-missing-#{unique()}.json")

  defp unique, do: System.unique_integer([:positive])

  defp restore_app(nil), do: Application.delete_env(:shadowops_core, :facebook_analytics_source)

  defp restore_app(path),
    do: Application.put_env(:shadowops_core, :facebook_analytics_source, path)

  defp restore_env(nil), do: System.delete_env("SHADOWOPS_FACEBOOK_ANALYTICS_SOURCE")
  defp restore_env(path), do: System.put_env("SHADOWOPS_FACEBOOK_ANALYTICS_SOURCE", path)
end
