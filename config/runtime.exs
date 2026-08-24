import Config

if token = System.get_env("SHADOWOPS_READ_TOKEN") do
  config :shadowops_web, read_token: token
end

if token = System.get_env("SHADOWOPS_WRITE_TOKEN") do
  config :shadowops_web, write_token: token
end

# Persistent control-plane state is explicit by design. Production deployment
# injects SHADOWOPS_STATE_DIR through the systemd drop-in. Avoid deriving state
# paths from the release checkout so state survives release rotation and config
# remains readable by Config.Reader in tests/tools without an :env option.
if state_dir = System.get_env("SHADOWOPS_STATE_DIR") do
  config :shadowops_core,
    approval_path: Path.join(state_dir, "approvals.jsonl"),
    audit_path: Path.join(state_dir, "audit.jsonl"),
    run_path: Path.join(state_dir, "runs.jsonl")
end
