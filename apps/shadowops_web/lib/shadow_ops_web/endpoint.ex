defmodule ShadowOpsWeb.Endpoint do
  @session_options [
    store: :cookie,
    key: "_shadowops_session",
    signing_salt: "shadowops-local-control-plane-v1",
    same_site: "Lax"
  ]

  use Phoenix.Endpoint, otp_app: :shadowops_web

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options], check_origin: :conn]
  )

  plug(Plug.Static,
    at: "/",
    from: :shadowops_web,
    gzip: false,
    only: ~w(assets favicon.ico)
  )

  plug(Plug.Static,
    at: "/vendor/phoenix",
    from: {:phoenix, "priv/static"},
    gzip: false,
    only: ~w(phoenix.mjs)
  )

  plug(Plug.Static,
    at: "/vendor/live-view",
    from: {:phoenix_live_view, "priv/static"},
    gzip: false,
    only: ~w(phoenix_live_view.esm.js)
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])
  plug(ShadowOpsWeb.Plugs.Security)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.Session, @session_options)
  plug(ShadowOpsWeb.Router)
end
