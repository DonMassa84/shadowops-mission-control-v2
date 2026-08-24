defmodule ShadowOpsCore.Repo do
  use Ecto.Repo,
    otp_app: :shadowops_core,
    adapter: Ecto.Adapters.Postgres
end
