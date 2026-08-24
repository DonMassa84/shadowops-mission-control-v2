defmodule ShadowOpsWeb.LearningController do
  use Phoenix.Controller, formats: [:json]

  alias ShadowOpsCore.LearningFocus

  def plan(conn, _params) do
    {:ok, plan} = LearningFocus.load()
    json(conn, plan)
  end
end
