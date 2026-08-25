defmodule ShadowOpsWeb.LayerHealthTest do
  use ExUnit.Case, async: false

  alias ShadowOpsWeb.LayerEvaluator

  test "layer evaluator is deterministic, read-only and truthful about missing evidence" do
    snapshot = LayerEvaluator.build_snapshot()

    assert snapshot.id == "layer-health"
    assert snapshot.total_layers == 12
    assert snapshot.assessed_layers in 0..12
    assert snapshot.real_data == true
    assert snapshot.synthetic == false
    assert snapshot.state in ~w(EXCELLENT HEALTHY REVIEW DEGRADED CRITICAL NOT_ASSESSED)

    assert snapshot.layers |> Enum.map(& &1.id) |> MapSet.new() ==
             MapSet.new(
               ~w(sources data_fabric data_quality lineage ontology identity relationships projects workflows runtime governance knowledge)
             )

    for layer <- snapshot.layers do
      assert layer.state in ~w(EXCELLENT HEALTHY REVIEW DEGRADED CRITICAL NOT_ASSESSED)

      if layer.assessed do
        assert is_integer(layer.score)
        assert layer.score in 0..100
        assert is_number(layer.coverage)
      else
        assert is_nil(layer.score)
        assert is_nil(layer.coverage)
        assert layer.state == "NOT_ASSESSED"
      end
    end
  end

  test "browser and read API routes render without a mutation route" do
    page = request(:get, "/layers", false)
    assert page.status == 200
    assert page.resp_body =~ "Layer Health"
    assert page.resp_body =~ "Layer health overview"

    api = request(:get, "/api/layers")
    assert api.status == 200
    body = Jason.decode!(api.resp_body)
    assert body["id"] == "layer-health"
    assert length(body["layers"]) == 12

    layer_id = body["layers"] |> hd() |> Map.fetch!("id")
    detail = request(:get, "/api/layers/#{layer_id}")
    assert detail.status == 200
    assert Jason.decode!(detail.resp_body)["id"] == layer_id

    unknown = request(:get, "/api/layers/not-a-real-layer")
    assert unknown.status == 404
    assert Jason.decode!(unknown.resp_body)["error"] == "layer_not_found"

    mutation = request(:post, "/api/layers", true, %{})
    assert mutation.status in [404, 405]
  end

  defp request(method, path, read_auth \\ true, params \\ nil) do
    conn =
      if params do
        Plug.Test.conn(method, path, Jason.encode!(params))
        |> Plug.Conn.put_req_header("content-type", "application/json")
      else
        Plug.Test.conn(method, path)
      end

    conn =
      if read_auth,
        do: Plug.Conn.put_req_header(conn, "x-shadowops-read", "1"),
        else: conn

    ShadowOpsWeb.Endpoint.call(conn, [])
  end
end
