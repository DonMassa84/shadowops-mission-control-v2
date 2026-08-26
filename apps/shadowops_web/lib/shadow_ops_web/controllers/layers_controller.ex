defmodule ShadowOpsWeb.LayersController do
  use Phoenix.Controller, formats: [:json]

  alias ShadowOpsWeb.LayerEvaluator

  def index(conn, _params), do: json(conn, LayerEvaluator.snapshot())

  def show(conn, %{"id" => id}) do
    case LayerEvaluator.layer(id) do
      {:ok, layer} ->
        json(conn, layer)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "layer_not_found", id: id})
    end
  end
end
