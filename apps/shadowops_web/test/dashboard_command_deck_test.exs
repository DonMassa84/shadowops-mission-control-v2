defmodule ShadowOpsWeb.DashboardCommandDeckTest do
  use ExUnit.Case, async: false

  alias ShadowOpsCore.RuntimeSources
  alias WorkflowEngine.WorkflowIds

  test "V2 dashboard exposes mission, attention, actions and source truth" do
    response =
      :get
      |> Plug.Test.conn("/")
      |> ShadowOpsWeb.Endpoint.call([])

    assert response.status == 200
    body = response.resp_body

    assert body =~ "Mission Control"
    assert body =~ ~r/current mission/i
    assert body =~ ~r/attention required/i
    assert body =~ ~r/top 3/i
    assert body =~ ~r/source truth/i
    assert body =~ ~r/daily control/i

    assert body =~ "IHK"
    assert body =~ "Evidence"
    assert body =~ "Knowledge"
    assert body =~ "Services"
    assert body =~ "Backups"

    refute body =~ "/home/schattenmacher/"
    refute body =~ "/tmp/shadowops"
  end

  test "source truth preserves evidence semantics and renders every required source" do
    response =
      :get
      |> Plug.Test.conn("/")
      |> ShadowOpsWeb.Endpoint.call([])

    assert response.status == 200
    body = response.resp_body

    for source <- ~w(system security audit ihk evidence knowledge services social career backups) do
      assert body =~ ~s(data-source-id="#{source}")
    end

    evidence = RuntimeSources.evidence()
    available = Enum.count(evidence.artifacts, &(&1.verification_status == "AVAILABLE"))
    verified = Enum.count(evidence.artifacts, &(&1.verification_status == "VERIFIED"))

    assert available > verified
    assert evidence.real_data == true
    assert evidence.synthetic == false

    evidence_card = source_card(body, "evidence")
    assert evidence_card =~ "Source status: READY"
    assert evidence_card =~ "Artifacts available: #{available}"
    assert evidence_card =~ "Artifacts verified: #{verified}"
    assert evidence_card =~ "Real data</dt><dd>true"
    assert evidence_card =~ "Synthetic</dt><dd>false"

    assert source_card(body, "ihk") =~ "READY"
  end

  test "top actions are bounded and one-click controls fail closed to registry truth" do
    response =
      :get
      |> Plug.Test.conn("/")
      |> ShadowOpsWeb.Endpoint.call([])

    assert response.status == 200
    body = response.resp_body

    assert length(Regex.scan(~r/data-role="top-action"/, body)) <= 3
    assert {:ok, daily_control_id} = WorkflowIds.canonical_id("daily_control")
    assert body =~ daily_control_id
    assert body =~ "REGISTERED_READ_ONLY"

    for label <- ["System Doctor", "IHK Evidence Gate", "Release Acceptance", "Career Control"] do
      assert body =~ label
    end

    assert length(Regex.scan(~r/data-role="one-click-unavailable"/, body)) == 4
    refute body =~ "/workflows/so:wf:v1:"
    refute body =~ ~r/(phx-click|data-action)="(run|execute)"/
  end

  test "V2 primary navigation exposes command, operations, intelligence and governance" do
    response =
      :get
      |> Plug.Test.conn("/")
      |> ShadowOpsWeb.Endpoint.call([])

    assert response.status == 200
    body = response.resp_body

    for path <- [
          "/daily-control",
          "/compute",
          "/workflows",
          "/runs",
          "/jobs",
          "/services",
          "/backups",
          "/knowledge",
          "/evidence",
          "/ai",
          "/agents",
          "/approvals",
          "/security",
          "/audit",
          "/logs",
          "/career",
          "/projects/ihk",
          "/integrations"
        ] do
      assert body =~ ~s(href="#{path}")
    end
  end

  defp source_card(body, id) do
    [card] =
      Regex.run(~r/<article class="mc-metric" data-source-id="#{id}">.*?<\/article>/s, body)

    card
  end
end
