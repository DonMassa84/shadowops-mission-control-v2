defmodule ShadowOpsWeb.ChatGPTProjectTest do
  use ExUnit.Case, async: false

  alias ShadowOpsWeb.{ProjectDomains, SourceRegistry}

  test "ChatGPT project domain is registered without fabricating connectivity" do
    domain = ProjectDomains.snapshot(:chatgpt)

    assert domain.id == "chatgpt"
    assert domain.name == "ChatGPT Project"
    assert domain.synthetic == false

    if domain.real_data do
      assert domain.reachable == true
    else
      assert domain.status == "NOT_CONFIGURED"
      assert domain.reachable == false
      assert domain.error_code in ["SOURCE_MISSING", "SOURCE_UNREADABLE", "INVALID_SCHEMA", "INVALID_JSON"]
    end
  end

  test "ChatGPT project source is registered as local import evidence" do
    source = SourceRegistry.snapshot("chatgpt_project")

    assert source.id == "chatgpt_project"
    assert source.name == "ChatGPT Project"
    assert "chatgpt" in source.domains
    assert source.synthetic == false

    if source.real_data do
      assert source.reachable == true
    else
      assert source.status in ["NOT_CONFIGURED", "UNAVAILABLE"]
      assert source.reachable == false
    end
  end

  test "ChatGPT project route renders" do
    conn = Plug.Test.conn(:get, "/projects/chatgpt")
    response = ShadowOpsWeb.Endpoint.call(conn, [])

    assert response.status == 200
    assert response.resp_body =~ "ChatGPT Project"
  end
end
