import Config

truthy? = fn value -> value in ["1", "true", "TRUE", "yes", "YES"] end

parse_integer! = fn name, value, range ->
  case Integer.parse(value) do
    {integer, ""} ->
      if integer in range do
        integer
      else
        raise "#{name} must be within #{inspect(range)}"
      end

    _ ->
      raise "#{name} must be an integer"
  end
end

required_secret! = fn name, minimum_bytes ->
  case System.get_env(name) do
    value when is_binary(value) and byte_size(value) >= minimum_bytes ->
      value

    _ ->
      raise "#{name} must be set and contain at least #{minimum_bytes} bytes"
  end
end

# Config.Reader.read!/1 is used by tests/tools without supplying :env. Keep the
# file inspectable there, while releases and Mix runtime evaluation still
# receive the real config environment and therefore enforce production gates.
runtime_env =
  try do
    config_env()
  rescue
    RuntimeError -> :unknown
  end

if token = System.get_env("SHADOWOPS_READ_TOKEN") do
  config :shadowops_web, read_token: token
end

if token = System.get_env("SHADOWOPS_WRITE_TOKEN") do
  config :shadowops_web, write_token: token
end

start_persistence = truthy?.(System.get_env("SHADOWOPS_START_PERSISTENCE", "false"))
config :shadowops_core, start_persistence: start_persistence

if start_persistence do
  pool_size =
    parse_integer!.(
      "SHADOWOPS_DB_POOL_SIZE",
      System.get_env("SHADOWOPS_DB_POOL_SIZE", "10"),
      1..100
    )

  password =
    if runtime_env == :prod do
      required_secret!.("SHADOWOPS_DB_PASSWORD", 16)
    else
      System.get_env("SHADOWOPS_DB_PASSWORD", "postgres")
    end

  config :shadowops_core, ShadowOpsCore.Repo,
    username: System.get_env("SHADOWOPS_DB_USER", "postgres"),
    password: password,
    hostname: System.get_env("SHADOWOPS_DB_HOST", "localhost"),
    database: System.get_env("SHADOWOPS_DB_NAME", "shadowops_dev"),
    pool_size: pool_size
end

# Persistent control-plane state is explicit by design. Production deployment
# injects SHADOWOPS_STATE_DIR so state survives release rotation.
if state_dir = System.get_env("SHADOWOPS_STATE_DIR") do
  state_dir = Path.expand(state_dir)

  config :shadowops_core,
    approval_path: Path.join(state_dir, "approvals.jsonl"),
    audit_path: Path.join(state_dir, "audit.jsonl"),
    run_path: Path.join(state_dir, "runs.jsonl")
end

if runtime_env == :prod do
  secret_key_base = required_secret!.("SHADOWOPS_SECRET_KEY_BASE", 64)
  read_token = required_secret!.("SHADOWOPS_READ_TOKEN", 32)

  if write_token = System.get_env("SHADOWOPS_WRITE_TOKEN") do
    if byte_size(write_token) < 32 do
      raise "SHADOWOPS_WRITE_TOKEN must contain at least 32 bytes when writes are enabled"
    end
  end

  port = parse_integer!.("PORT", System.get_env("PORT", "4013"), 1..65_535)

  config :shadowops_web, read_token: read_token

  # ShadowOps is a local control plane. Production remains loopback-only; remote
  # access must be provided by an authenticated tunnel/reverse proxy.
  config :shadowops_web, ShadowOpsWeb.Endpoint,
    server: true,
    url: [host: System.get_env("SHADOWOPS_PUBLIC_HOST", "localhost"), port: port, scheme: "http"],
    http: [ip: {127, 0, 0, 1}, port: port],
    secret_key_base: secret_key_base
end
