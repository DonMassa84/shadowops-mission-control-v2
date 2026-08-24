defmodule ShadowOpsWeb.FacebookBalanceRouteTest do
  use ExUnit.Case, async: false

  alias ShadowOps.Social.FacebookCommunicationBalance, as: Balance

  setup do
    previous_balance = Application.get_env(:shadowops_core, :facebook_balance_source)
    previous_runtime = Application.get_env(:shadowops_core, :facebook_runtime_source)
    balance_path = balance_fixture()
    runtime_path = fixture(runtime())

    Application.put_env(:shadowops_core, :facebook_balance_source, balance_path)
    Application.put_env(:shadowops_core, :facebook_runtime_source, runtime_path)

    on_exit(fn ->
      restore(:facebook_balance_source, previous_balance)
      restore(:facebook_runtime_source, previous_runtime)
    end)

    %{balance_path: balance_path}
  end

  test "privacy-safe Facebook balance API route is registered once" do
    routes = Phoenix.Router.routes(ShadowOpsWeb.Router)
    assert Enum.count(routes, &(&1.path == "/api/social/facebook/balance")) == 1
  end

  test "API exposes only the classifier output contract" do
    response = request("/api/social/facebook/balance")
    assert response.status == 200
    body = Jason.decode!(response.resp_body)

    assert body["status"] == "BALANCE_CLASSIFIER_READY"

    assert body["counts"] == %{
             "BALANCED" => 1,
             "WATCH" => 1,
             "OVERINVESTING" => 0,
             "INSUFFICIENT_DATA" => 0
           }

    assert Enum.map(body["chats"], & &1["chat"]) ==
             ~w(C_0123456789abcdef C_1111111111111111)

    assert Enum.all?(body["chats"], &(&1["privacy"] == "PSEUDONYMIZED_AGGREGATE"))
    assert body["privacy"]["raw_messages"] == false
    assert body["privacy"]["raw_names"] == false

    for forbidden <- ~w(RAW_NAME_SENTINEL RAW_MESSAGE_SENTINEL person@example.invalid) do
      refute response.resp_body =~ forbidden
    end
  end

  test "Mission Control renders communication balance without changing Facebook readiness" do
    response = request("/social/facebook")

    assert response.status == 200
    assert response.resp_body =~ "COMMUNICATION BALANCE"
    assert response.resp_body =~ "BALANCE_CLASSIFIER_READY"
    assert response.resp_body =~ "C_0123456789abcdef"
    assert response.resp_body =~ "PSEUDONYMIZED_AGGREGATE"
    assert response.resp_body =~ "FACEBOOK_METRICS_READY"
    assert response.resp_body =~ "CONTACT_RANKING_READY"
    assert response.resp_body =~ "READY"
    refute response.resp_body =~ "RAW_NAME_SENTINEL"
    refute response.resp_body =~ "RAW_MESSAGE_SENTINEL"
  end

  test "missing balance snapshot fails closed while existing Facebook runtime remains ready" do
    Application.put_env(:shadowops_core, :facebook_balance_source, missing_path())

    api = request("/api/social/facebook/balance")
    assert Jason.decode!(api.resp_body)["status"] == "UNAVAILABLE"

    facebook = request("/social/facebook")
    assert facebook.resp_body =~ "BALANCE CLASSIFIER NOT AVAILABLE"
    assert facebook.resp_body =~ "FACEBOOK_METRICS_READY"
    assert facebook.resp_body =~ "CONTACT_RANKING_READY"
  end

  defp balance_fixture do
    ranking = %{
      "status" => "CONTACT_RANKING_READY",
      "total_one_to_one_chats" => 2,
      "contacts" => [contact("C_1111111111111111", 0.50, 0.70), contact()],
      "privacy" => %{
        "raw_names" => false,
        "raw_messages" => false,
        "media" => false,
        "chat_ids_pseudonymous" => true
      }
    }

    path = fixture_path()

    assert {:ok, snapshot} =
             Balance.build(ranking,
               generated_at: "2026-08-23T20:00:00Z",
               source_commit: "abc123",
               source_sha256: String.duplicate("a", 64)
             )

    File.write!(path, Jason.encode!(snapshot))
    path
  end

  defp contact(chat \\ "C_0123456789abcdef", outbound \\ 0.50, initiation \\ 0.50) do
    %{
      "chat" => chat,
      "messages" => 100,
      "inbound" => 50,
      "outbound" => 50,
      "outbound_share_me" => outbound,
      "sessions" => 20,
      "initiations_me" => 10,
      "initiations_other" => 10,
      "initiation_share_me" => initiation,
      "followups_me_ge30m" => 2,
      "followups_other_ge30m" => 2,
      "median_response_seconds_me" => 30.0,
      "median_response_seconds_other" => 30.0,
      "p90_response_seconds_me" => 120.0,
      "p90_response_seconds_other" => 120.0,
      "category" => "ausgeglichen"
    }
  end

  defp runtime do
    Jason.encode!(%{
      "status" => "FACEBOOK_RUNTIME_READY",
      "generated_at" => "2026-08-23T18:00:00Z",
      "source_commit" => "abc123",
      "metrics_status" => "FACEBOOK_METRICS_READY",
      "ranking_status" => "CONTACT_RANKING_READY",
      "all_chats" => %{"messages" => 200, "chats" => 2},
      "one_to_one" => %{
        "messages" => 200,
        "chats" => 2,
        "inbound" => 100,
        "outbound" => 100,
        "reciprocity_balance" => 1.0,
        "initiation_share_me" => 0.5,
        "median_response_seconds_me" => 30.0,
        "median_response_seconds_other" => 30.0,
        "followups_without_direction_change_ge30m_me" => 2,
        "followups_without_direction_change_ge30m_other" => 2
      },
      "yearly_one_to_one" => [],
      "total_one_to_one_chats" => 2,
      "categories" => %{"ausgeglichen" => 2},
      "privacy" => %{
        "aggregate_only" => true,
        "raw_messages" => false,
        "raw_names" => false,
        "media" => false,
        "contact_records" => false
      }
    })
  end

  defp request(path) do
    :get
    |> Plug.Test.conn(path)
    |> ShadowOpsWeb.Endpoint.call([])
  end

  defp fixture(contents) do
    path = fixture_path()
    File.write!(path, contents)
    path
  end

  defp fixture_path do
    path = Path.join(System.tmp_dir!(), "facebook-balance-route-#{unique()}.json")
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp missing_path,
    do: Path.join(System.tmp_dir!(), "facebook-balance-route-missing-#{unique()}.json")

  defp restore(key, nil), do: Application.delete_env(:shadowops_core, key)
  defp restore(key, value), do: Application.put_env(:shadowops_core, key, value)
  defp unique, do: System.unique_integer([:positive])
end
