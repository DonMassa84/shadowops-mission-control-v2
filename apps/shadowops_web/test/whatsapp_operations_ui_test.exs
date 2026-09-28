defmodule ShadowOpsWeb.WhatsAppOperationsUITest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint ShadowOpsWeb.Endpoint

  test "WhatsApp brings source evidence and registered workflows into one read-only view" do
    {:ok, view, html} = live(build_conn(), "/social/whatsapp")

    assert html =~ "WhatsApp operations"
    assert has_element?(view, "#whatsapp-workflows")
    assert html =~ "whatsapp-status"
    assert html =~ "whatsapp-retry-all"
    assert html =~ "EXTERNAL_REGISTRY_ONLY"
    assert html =~ "Last run not evidenced"
    assert has_element?(view, "a[href='/approvals']")
    assert has_element?(view, "a[href='/audit']")
    refute has_element?(view, "[phx-click='one_click_run']")
  end

  test "registry failure keeps the connector view usable without claiming an empty inventory" do
    previous = Application.fetch_env!(:workflow_engine, :registry_path)
    Application.put_env(:workflow_engine, :registry_path, "/missing/whatsapp-registry.yaml")
    on_exit(fn -> Application.put_env(:workflow_engine, :registry_path, previous) end)

    {:ok, view, html} = live(build_conn(), "/social/whatsapp")
    assert html =~ "Workflow inventory unavailable"
    assert html =~ "Connector contract"
    refute has_element?(view, "#whatsapp-workflows tbody tr")
  end

  test "other social connectors do not display the WhatsApp workflow pack" do
    {:ok, view, _html} = live(build_conn(), "/social/telegram")
    refute has_element?(view, "#whatsapp-workflows")
  end
end
