defmodule ShadowOpsWeb.RemoteAIPolicyContractTest do
  use ExUnit.Case, async: false

  test "AI UI exposes remote-only policy without local model inventory" do
    response = request(:get, "/ai")

    assert response.status == 200
    assert response.resp_body =~ "AI Governance"
    assert response.resp_body =~ "REMOTE_ONLY"
    assert response.resp_body =~ "Local LLM runtime"
    assert response.resp_body =~ "DISABLED"
    assert response.resp_body =~ "Fallback"
    assert response.resp_body =~ "NONE"
    refute response.resp_body =~ "Installed local Ollama models"
    refute response.resp_body =~ "Installed models"
  end

  test "AI API exposes no local model records" do
    response = request(:get, "/api/ai")

    assert response.status == 200
    payload = Jason.decode!(response.resp_body)

    assert payload["models"] == []
    assert payload["loaded_models"] == []
    assert payload["policy"]["coding_execution"] == "REMOTE_ONLY"
    assert payload["policy"]["local_llm_runtime"] == "DISABLED"
    assert payload["policy"]["local_coding_fallback"] == "FORBIDDEN"
    assert payload["policy"]["fallback"] == "NONE"
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
