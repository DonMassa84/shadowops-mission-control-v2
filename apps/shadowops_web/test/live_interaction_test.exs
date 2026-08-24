defmodule ShadowOpsWeb.LiveInteractionTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias ShadowOpsCore.Audit

  @endpoint ShadowOpsWeb.Endpoint

  test "connected dashboard remains alive when security self-check fails closed" do
    previous = Application.get_env(:shadowops_web, :write_token)
    Application.delete_env(:shadowops_web, :write_token)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:shadowops_web, :write_token, previous),
        else: Application.delete_env(:shadowops_web, :write_token)
    end)

    {:ok, view, html} = live(build_conn(), "/")
    assert html =~ "Mission Control"

    send(view.pid, :refresh)
    Process.sleep(100)

    assert Process.alive?(view.pid)
    rendered = render(view)
    assert rendered =~ "Security"
    assert rendered =~ "Write API remains approval-gated"
  end

  test "workflow filters update the connected LiveView without a page reload" do
    {:ok, view, html} = live(build_conn(), "/workflows")
    assert html =~ "Finanzabgleich"

    filtered =
      render_change(view, "filter", %{
        "search" => "repository",
        "category" => "",
        "domain" => "",
        "status" => "",
        "runtime" => "",
        "sort" => "id"
      })

    assert filtered =~ "Repository quality"
    refute filtered =~ "Finanzabgleich"

    system = filter(view, %{"category" => "system"})
    assert system =~ "Repository quality" and system =~ "Finance quality gate"
    refute system =~ "Finanzabgleich"

    finance = filter(view, %{"domain" => "finance"})
    assert finance =~ "Finanzabgleich"
    refute finance =~ "Repository quality"

    active = filter(view, %{"status" => "active"})
    assert active =~ "Finanzabgleich" and active =~ "Repository quality"
    refute active =~ "Document ai"

    github_actions = filter(view, %{"runtime" => "github_actions"})
    assert github_actions =~ "Repository quality" and github_actions =~ "Finance quality gate"
    refute github_actions =~ "Career email only"

    sorted = filter(view, %{"sort" => "domain"})
    assert sorted =~ ~r/Career email only.*Repository quality.*Document ai.*Finanzabgleich/s

    cleared = render_click(view, "clear")
    assert cleared =~ "Finanzabgleich" and cleared =~ "Repository quality"
  end

  test "audit filters and chain verification are live read actions" do
    previous = Application.get_env(:shadowops_core, :audit_path)

    path =
      Path.join(
        System.tmp_dir!(),
        "shadowops-audit-live-#{System.unique_integer([:positive])}.jsonl"
      )

    Application.put_env(:shadowops_core, :audit_path, path)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:shadowops_core, :audit_path, previous),
        else: Application.delete_env(:shadowops_core, :audit_path)

      File.rm(path)
    end)

    assert {:ok, _} = Audit.record(:requested, "alice", "workflow-a", :success)
    assert {:ok, _} = Audit.record(:requested, "bob", "workflow-b", :blocked)
    {:ok, view, html} = live(build_conn(), "/audit")
    assert html =~ "alice" and html =~ "bob"

    filtered =
      render_change(view, "filter", %{
        "actor" => "alice",
        "action" => "",
        "result" => "",
        "date" => ""
      })

    assert filtered =~ "alice"
    refute filtered =~ "bob"
    assert render_click(view, "verify") =~ "VALID"
  end

  defp filter(view, values) do
    render_change(
      view,
      "filter",
      Map.merge(
        %{
          "search" => "",
          "category" => "",
          "domain" => "",
          "status" => "",
          "runtime" => "",
          "sort" => "id"
        },
        values
      )
    )
  end
end
