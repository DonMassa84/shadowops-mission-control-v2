defmodule ShadowOpsWeb.FacebookRouteTest do
  use ExUnit.Case, async: false

  @valid """
  {"generated_at":"2026-08-20T21:08:56+02:00","privacy":"aggregate-only","evidence":[{"path":"aggregate_source.ex","sha256":"abc","priority":true,"dimensions":["score_weight"],"matches":[{"line":39,"text":"power_score = interactions / 1000"}],"message":"PRIVATE_MESSAGE_SENTINEL","name":"PRIVATE_NAME_SENTINEL","email":"PRIVATE_EMAIL_SENTINEL","phone":"PRIVATE_PHONE_SENTINEL","token":"PRIVATE_TOKEN_SENTINEL"}],"buckets":[{"path":"aggregate_source.ex","sha256":"def","chain":[]}],"dimension_status":{"volume":{"status":"VERIFIED"},"initiation":{"status":"MISSING"},"reply_response":{"status":"MISSING"},"latency":{"status":"MISSING"},"follow_up":{"status":"PARTIAL"},"reciprocity":{"status":"MISSING"},"balance":{"status":"MISSING"},"score_weight":{"status":"VERIFIED"},"threshold_class":{"status":"VERIFIED"},"ranking":{"status":"VERIFIED"}}}
  """

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
    path = missing_runtime_path()
    Application.put_env(:shadowops_core, :facebook_runtime_source, path)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:shadowops_core, :facebook_runtime_source, previous),
        else: Application.delete_env(:shadowops_core, :facebook_runtime_source)
    end)

    :ok
  end

  test "Facebook and Social Review routes are registered exactly once" do
    routes = Phoenix.Router.routes(ShadowOpsWeb.Router)
    assert Enum.count(routes, &(&1.path == "/social/facebook")) == 1
    assert Enum.count(routes, &(&1.path == "/social/review")) == 1
    assert Enum.count(routes, &(&1.path == "/api/social")) == 1
  end

  test "missing private Facebook source renders explicit unavailable states" do
    configure_source(missing_path())

    facebook = request("/social/facebook")
    assert facebook.status == 200
    assert facebook.resp_body =~ "FACEBOOK DATA NOT AVAILABLE"
    assert facebook.resp_body =~ "NOT_AVAILABLE"
    assert facebook.resp_body =~ "PROTECTED"
    assert facebook.resp_body =~ ~r/<small>TOTAL EVENTS<\/small><strong>N\/A<\/strong>/
    refute facebook.resp_body =~ "<strong>0</strong>"

    review = request("/social/review")
    assert review.status == 200
    assert review.resp_body =~ "Social Review"
    assert review.resp_body =~ "UNAVAILABLE"
    assert review.resp_body =~ "N/A"
  end

  test "real aggregate runtime renders READY with source-backed KPIs" do
    configure_source(fixture(@valid))
    Application.put_env(:shadowops_core, :facebook_runtime_source, fixture(@runtime))

    facebook = request("/social/facebook")
    assert facebook.status == 200
    assert facebook.resp_body =~ "READY"
    assert facebook.resp_body =~ "FACEBOOK_METRICS_READY"
    assert facebook.resp_body =~ "CONTACT_RANKING_READY"
    assert facebook.resp_body =~ "77273"
    assert facebook.resp_body =~ "76112"
    assert facebook.resp_body =~ "584"
    assert facebook.resp_body =~ "aggregate only" or facebook.resp_body =~ "AGGREGATE ONLY"
  end

  test "Social Review renders real evidence counts and only source-backed dimension states" do
    configure_source(fixture(@valid))
    response = request("/social/review")

    assert response.status == 200
    assert response.resp_body =~ "Evidence records"
    assert response.resp_body =~ "Buckets"
    assert response.resp_body =~ "Verified dimensions"
    assert response.resp_body =~ "Follow-up"
    assert response.resp_body =~ "PARTIAL"
    assert response.resp_body =~ "Reciprocity"
    assert response.resp_body =~ "UNAVAILABLE"
    assert response.resp_body =~ "FULL_SOCIAL_HEALTH_SCORE"
    refute response.resp_body =~ "0%"
  end

  test "Social Review never renders private field values" do
    configure_source(fixture(@valid))
    body = request("/social/review").resp_body

    for sentinel <-
          ~w(PRIVATE_MESSAGE_SENTINEL PRIVATE_NAME_SENTINEL PRIVATE_EMAIL_SENTINEL PRIVATE_PHONE_SENTINEL PRIVATE_TOKEN_SENTINEL) do
      refute body =~ sentinel
    end

    refute body =~ "power_score = interactions / 1000"
    refute body =~ "aggregate_source.ex"
  end

  test "all malformed source cases keep both LiveViews at HTTP 200" do
    configure_source(missing_path())

    root = Path.join(System.tmp_dir!(), "facebook-negative-routes-#{unique()}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)

    cases = [
      {"empty", ""},
      {"invalid", "not json"},
      {"array", "[]"},
      {"bom", <<0xEF, 0xBB, 0xBF>> <> @valid},
      {"missing-evidence", ~s({"buckets":[],"dimension_status":{}})},
      {"malformed-dimension-status", ~s({"evidence":[],"buckets":[],"dimension_status":[]})},
      {"truncated", ~s({"evidence":[)}
    ]

    Enum.each(cases, fn {name, contents} ->
      path = Path.join(root, name <> ".json")
      File.write!(path, contents)
      Application.put_env(:shadowops_core, :facebook_analytics_source, path)
      assert_safe_routes()
    end)

    directory = Path.join(root, "directory-source")
    File.mkdir!(directory)
    Application.put_env(:shadowops_core, :facebook_analytics_source, directory)
    assert_safe_routes()
  end

  test "malformed contact distribution is unavailable rather than synthetic" do
    data = @valid |> Jason.decode!() |> Map.put("contact_distribution", "malformed")
    configure_source(fixture(Jason.encode!(data)))

    response = request("/social/review")
    assert response.status == 200
    assert response.resp_body =~ "Contact distribution"
    assert response.resp_body =~ "UNAVAILABLE"
    refute response.resp_body =~ "contact score"
    refute response.resp_body =~ "response rate"
  end

  defp assert_safe_routes do
    Enum.each(~w(/social/facebook /social/review), fn route ->
      response = request(route)
      assert response.status == 200
      refute response.resp_body =~ "PRIVATE_"
      refute response.resp_body =~ "<strong>0</strong>"
    end)
  end

  defp configure_source(path) do
    previous = Application.get_env(:shadowops_core, :facebook_analytics_source)
    Application.put_env(:shadowops_core, :facebook_analytics_source, path)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:shadowops_core, :facebook_analytics_source, previous),
        else: Application.delete_env(:shadowops_core, :facebook_analytics_source)
    end)
  end

  defp request(path) do
    :get
    |> Plug.Test.conn(path)
    |> ShadowOpsWeb.Endpoint.call([])
  end

  defp fixture(contents) do
    path = Path.join(System.tmp_dir!(), "facebook-route-#{unique()}.json")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp missing_path, do: Path.join(System.tmp_dir!(), "facebook-route-missing-#{unique()}.json")

  defp missing_runtime_path,
    do: Path.join(System.tmp_dir!(), "facebook-runtime-route-missing-#{unique()}.json")

  defp unique, do: System.unique_integer([:positive])
end
