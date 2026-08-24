defmodule ShadowOpsWeb.LegalRouteTest do
  use ExUnit.Case, async: true
  use Plug.Test

  @opts ShadowOpsWeb.Router.init([])

  test "GET /api/legal returns redacted metadata only" do
    conn =
      conn(:get, "/api/legal")
      |> put_req_header("accept", "application/json")
      |> put_req_header("x-shadowops-read", "1")
      |> ShadowOpsWeb.Router.call(@opts)

    assert conn.status in [200, 401, 403]

    if conn.status == 200 do
      body = Jason.decode!(conn.resp_body)
      assert body["kind"] == "legal"
      assert body["privacy"]["classification"] == "LEGAL_PRIVATE"
      refute conn.resp_body =~ "/home/"
      refute Regex.match?(~r/DE\d{20}/, conn.resp_body)
    end
  end
end
