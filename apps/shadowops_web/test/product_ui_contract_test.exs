defmodule ShadowOpsWeb.ProductUIContractTest do
  use ExUnit.Case, async: false

  @root Path.expand("../../..", __DIR__)

  test "AI surface presents remote-only execution without local Ollama LLM inventory" do
    response = request(:get, "/ai")

    assert response.status == 200
    assert response.resp_body =~ "AI Governance"
    assert response.resp_body =~ "REMOTE_ONLY"
    assert response.resp_body =~ "Local LLM runtime"
    assert response.resp_body =~ "DISABLED"
    assert response.resp_body =~ "Local LLM inventory disabled"
    refute response.resp_body =~ "OLLAMA LOCAL"
    refute response.resp_body =~ "Product AI runtime"
    refute response.resp_body =~ "ollama_runtime"
    refute response.resp_body =~ "Inventory is not certification"
  end

  test "Mission Control ships an accessible command palette and keyboard navigation" do
    js = File.read!(Path.join(@root, "apps/shadowops_web/priv/static/assets/mission-control.js"))

    css =
      File.read!(
        Path.join(@root, "apps/shadowops_web/priv/static/assets/mission-control-command.css")
      )

    assert js =~ "mc-command-palette"
    assert js =~ "Ctrl K"
    assert js =~ "ArrowDown"
    assert js =~ "ArrowUp"
    assert js =~ "AI Governance"
    assert js =~ "remote only ai policy"
    refute js =~ "governed local product runtime"

    assert css =~ ".mc-palette-dialog"
    assert css =~ ".mc-command-trigger"
    assert css =~ "prefers-reduced-motion"
    assert css =~ "@media(max-width:560px)"
  end

  test "product UI keeps LiveView as the canonical client runtime" do
    js = File.read!(Path.join(@root, "apps/shadowops_web/priv/static/assets/mission-control.js"))

    assert js =~ "new LiveSocket"
    assert js =~ "liveSocket.connect()"
    refute js =~ "ReactDOM"
    refute js =~ "createRoot("
  end

  defp request(method, path) do
    method
    |> Plug.Test.conn(path)
    |> maybe_read_authorize()
    |> ShadowOpsWeb.Endpoint.call([])
  end

  defp maybe_read_authorize(conn) do
    case Application.get_env(:shadowops_web, :read_token) do
      token when is_binary(token) and byte_size(token) > 0 ->
        Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")

      _ ->
        conn
    end
  end
end
