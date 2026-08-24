import Config

registry_path = Path.expand("../../config/workflow_registry_v2.yaml", __DIR__)

config :workflow_engine,
  registry_path: registry_path

config :shadowops_core,
  ecto_repos: [ShadowOpsCore.Repo],
  start_persistence: System.get_env("SHADOWOPS_START_PERSISTENCE", "false") == "true"

config :shadowops_core, ShadowOpsCore.Repo,
  username: System.get_env("SHADOWOPS_DB_USER", "postgres"),
  password: System.get_env("SHADOWOPS_DB_PASSWORD", "postgres"),
  hostname: System.get_env("SHADOWOPS_DB_HOST", "localhost"),
  database: System.get_env("SHADOWOPS_DB_NAME", "shadowops_dev"),
  pool_size: String.to_integer(System.get_env("SHADOWOPS_DB_POOL_SIZE", "10"))

config :shadowops_core, Oban,
  repo: ShadowOpsCore.Repo,
  queues: [default: 5, workflows: 10, agents: 20],
  plugins: [Oban.Plugins.Pruner]

config :shadowops_web, ShadowOpsWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}, port: System.get_env("PORT") || 4000],
  secret_key_base: System.get_env("SHADOWOPS_SECRET_KEY_BASE") || String.duplicate("0", 64),
  render_errors: [formats: [json: ShadowOpsWeb.ErrorJSON], layout: false],
  pubsub_server: ShadowOpsWeb.PubSub,
  live_view: [signing_salt: "GM1mxh4oCLxBQRzG"]

config :phoenix, :json_library, Jason
