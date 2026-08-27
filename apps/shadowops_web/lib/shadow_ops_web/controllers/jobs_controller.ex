defmodule ShadowOpsWeb.JobsController do
  use Phoenix.Controller, formats: [:json]

  alias ShadowOpsCore.JobQueue

  def index(conn, _params), do: json(conn, JobQueue.snapshot())
end
