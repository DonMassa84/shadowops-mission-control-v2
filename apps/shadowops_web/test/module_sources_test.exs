defmodule ShadowOpsWeb.ModuleSourcesTest do
  use ExUnit.Case, async: false

  @required_api_routes ~w(
    /api/health
    /api/ready
    /api/system
    /api/workflows
    /api/runs
    /api/nodes
    /api/services
    /api/agents
    /api/ai
    /api/security/status
    /api/approvals
    /api/audit
    /api/logs
    /api/connectors
    /api/connectors/whatsapp
    /api/social
    /api/knowledge
    /api/backups
  )

  test "required read-only module APIs are routed and return real-source payloads" do
    for path <- @required_api_routes do
      response = request(path)
      assert response.status == 200, "#{path} returned #{response.status}: #{response.resp_body}"
      assert is_map(Jason.decode!(response.resp_body))
    end
  end

  test "all connector payloads implement the canonical contract" do
    body = request("/api/connectors") |> Map.fetch!(:resp_body) |> Jason.decode!()

    for connector <- body["records"] do
      for field <-
            ~w(id name kind status health source_type real_data synthetic enabled reachable metadata) do
        assert Map.has_key?(connector, field), "#{connector["id"]} is missing #{field}"
      end

      refute connector["synthetic"] == true and connector["status"] in ~w(CONNECTED ONLINE READY)

      refute connector["source_type"] in ~w(HISTORICAL ANALYTICS_ONLY IMPORT) and
               connector["status"] in ~w(CONNECTED ONLINE READY)
    end
  end

  test "external command failure does not incorrectly fail core health" do
    previous_path = System.get_env("PATH")
    System.put_env("PATH", Path.join(System.tmp_dir!(), "shadowops-no-external-commands"))

    on_exit(fn ->
      if previous_path, do: System.put_env("PATH", previous_path), else: System.delete_env("PATH")
    end)

    assert request("/api/health").status == 200
  end

  test "Facebook reconstruction without a verified runtime is never classified as live" do
    previous = Application.get_env(:shadowops_core, :facebook_runtime_source)
    missing = Path.join(System.tmp_dir!(), "facebook-module-source-missing-#{unique()}.json")
    Application.put_env(:shadowops_core, :facebook_runtime_source, missing)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:shadowops_core, :facebook_runtime_source, previous),
        else: Application.delete_env(:shadowops_core, :facebook_runtime_source)
    end)

    social = request("/api/social") |> Map.fetch!(:resp_body) |> Jason.decode!()
    facebook = Enum.find(social["records"], &(&1["id"] == "facebook"))

    assert facebook["source_type"] == "ANALYTICS_ONLY"
    refute facebook["status"] in ~w(CONNECTED ONLINE READY)
  end

  test "optional unconfigured IHK workflow cannot be executed" do
    assert {:ok, workflow} = ShadowOpsApi.get_workflow("career_funnel_ihk")
    assert workflow["execution_status"] == "DISABLED_BY_CONFIGURATION"
    refute workflow["executable"]

    assert {:error, {:workflow_not_executable, "DISABLED_BY_CONFIGURATION"}} =
             ShadowOpsApi.execute_workflow("career_funnel_ihk", "test", %{})
  end

  defp request(path) do
    Plug.Test.conn(:get, path)
    |> ShadowOpsWeb.Router.call(ShadowOpsWeb.Router.init([]))
  end

  defp unique, do: System.unique_integer([:positive])
end
