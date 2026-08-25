import Config

registry_path = Path.expand("../../config/workflow_registry_v2.yaml", __DIR__)
port = System.get_env("PORT", "4000") |> String.to_integer()

config :workflow_engine,
  registry_path: registry_path

# Runtime-specific persistence and credentials are resolved in runtime.exs.
# Keep the compile-time/default configuration inert and local-safe.
config :shadowops_core,
  ecto_repos: [ShadowOpsCore.Repo],
  start_persistence: false

config :shadowops_core, ShadowOpsCore.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "shadowops_dev",
  pool_size: 10

config :shadowops_core, Oban,
  repo: ShadowOpsCore.Repo,
  queues: [default: 5, workflows: 10, agents: 20],
  plugins: [Oban.Plugins.Pruner]

config :shadowops_web, ShadowOpsWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}, port: port],
  secret_key_base: System.get_env("SHADOWOPS_SECRET_KEY_BASE") || String.duplicate("0", 64),
  render_errors: [formats: [json: ShadowOpsWeb.ErrorJSON], layout: false],
  pubsub_server: ShadowOpsWeb.PubSub,
  live_view: [signing_salt: "GM1mxh4oCLxBQRzG"]

config :phoenix, :json_library, Jason
