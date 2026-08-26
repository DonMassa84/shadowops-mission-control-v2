defmodule ShadowOpsWeb.RemoteAIUIPolicyTest do
  use ExUnit.Case, async: false

  test "AI surface presents remote-only execution and never promotes local inventory" do
    response = request("/ai")

    assert response.status == 200
    assert response.resp_body =~ "AI Policy"
    assert response.resp_body =~ "REMOTE ONLY"
    assert response.resp_body =~ "Local inference"
    assert response.resp_body =~ "BLOCKED"
    assert response.resp_body =~ "Local runtime inventory"
    assert response.resp_body =~ "AI · Remote only"

    refute response.resp_body =~ "Installed local Ollama models"
    refute response.resp_body =~ "Only models returned by the real Ollama CLI are listed"
  end

  test "dashboard exposes policy separately from local AI inventory" do
    response = request("/")

    assert response.status == 200
    assert response.resp_body =~ "remote-only AI"
    assert response.resp_body =~ "AI policy"
    assert response.resp_body =~ "REMOTE ONLY"
    assert response.resp_body =~ "AI execution policy"
    assert response.resp_body =~ "execution blocked"

    refute response.resp_body =~ "Local model/runtime evidence"
    refute response.resp_body =~ "OpenCode, Codex and local agents only when evidenced"
  end

  test "Mission Control shell loads the refresh layer" do
    dashboard = request("/")
    assert dashboard.resp_body =~ ~s(href="/assets/mission-control-refresh.css")

    css = request("/assets/mission-control-refresh.css")
    assert css.status == 200
    assert css.resp_body =~ ".mc-policy-chip"
    assert css.resp_body =~ "@media(max-width:900px)"
    assert css.resp_body =~ "grid-template-columns:repeat(2,minmax(0,1fr))"
    assert css.resp_body =~ "@media(prefers-contrast:more)"
  end

  defp request(path) do
    path
    |> Plug.Test.conn(:get)
    |> ShadowOpsWeb.Endpoint.call([])
  end
end
