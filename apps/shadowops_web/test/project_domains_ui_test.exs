defmodule ShadowOpsWeb.ProjectDomainsUITest do
  use ExUnit.Case, async: false

  test "project domain hub and detail routes stay fail-visible without local manifests" do
    hub = request("/projects")
    assert hub.status == 200
    assert hub.resp_body =~ "Project domains"
    assert hub.resp_body =~ "Finance"
    assert hub.resp_body =~ "Investigations"
    assert hub.resp_body =~ "IHK"
    assert hub.resp_body =~ "Community"
    assert hub.resp_body =~ "NOT_CONFIGURED"

    for path <- ~w(/projects/finance /projects/investigations /projects/ihk /projects/community) do
      response = request(path)
      assert response.status == 200
      assert response.resp_body =~ "LOCAL_JSON_MANIFEST"
      assert response.resp_body =~ "No local manifest is configured"
    end
  end

  defp request(path) do
    :get
    |> Plug.Test.conn(path)
    |> ShadowOpsWeb.Endpoint.call([])
  end
end
