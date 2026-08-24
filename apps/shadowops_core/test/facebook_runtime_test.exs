defmodule ShadowOps.Social.FacebookRuntimeTest do
  use ExUnit.Case, async: false

  alias ShadowOps.Social.FacebookRuntime

  test "accepts only a real aggregate-only runtime contract" do
    path = fixture(valid_contract())
    assert {:ok, runtime} = FacebookRuntime.load(path)
    assert runtime.status == "READY"
    assert runtime.ready?
    assert runtime.source.sha256
    assert runtime.metrics["TOTAL MESSAGES"] == 12

    unsafe = valid_contract() |> put_in(["privacy", "aggregate_only"], false)

    assert {:ok, %{status: "UNAVAILABLE", ready?: false}} =
             FacebookRuntime.load(fixture(unsafe))

    private = Map.put(valid_contract(), "contacts", [%{"private" => true}])

    assert {:ok, %{status: "UNAVAILABLE", ready?: false}} =
             FacebookRuntime.load(fixture(private))
  end

  test "missing and malformed sources fail closed" do
    missing = Path.join(System.tmp_dir!(), "facebook-runtime-missing-#{unique()}.json")
    assert {:ok, %{status: "UNAVAILABLE", metrics: %{}}} = FacebookRuntime.load(missing)
    assert {:ok, %{status: "UNAVAILABLE", metrics: %{}}} = FacebookRuntime.load(fixture("bad"))
  end

  defp valid_contract do
    %{
      "status" => "FACEBOOK_RUNTIME_READY",
      "generated_at" => "2026-08-23T18:00:00Z",
      "source_commit" => "test-commit",
      "metrics_status" => "FACEBOOK_METRICS_READY",
      "ranking_status" => "CONTACT_RANKING_READY",
      "all_chats" => %{"messages" => 12, "chats" => 3},
      "one_to_one" => %{"messages" => 10, "chats" => 2},
      "categories" => %{},
      "privacy" => %{
        "aggregate_only" => true,
        "raw_messages" => false,
        "raw_names" => false,
        "media" => false,
        "contact_records" => false
      }
    }
  end

  defp fixture(data) do
    path = Path.join(System.tmp_dir!(), "facebook-runtime-#{unique()}.json")
    body = if(is_binary(data), do: data, else: Jason.encode!(data))
    File.write!(path, body)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp unique, do: System.unique_integer([:positive])
end
