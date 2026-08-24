defmodule ShadowOpsWeb.SourceRegistryTest do
  use ExUnit.Case, async: false

  alias ShadowOpsWeb.SourceRegistry

  setup do
    root = Path.join(System.tmp_dir!(), "shadowops-imports-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)

    previous_dir = System.get_env("SHADOWOPS_IMPORT_DIR")
    System.put_env("SHADOWOPS_IMPORT_DIR", root)

    tracked = ~w(GMAIL_CLIENT_ID GMAIL_CLIENT_SECRET GMAIL_REFRESH_TOKEN GITHUB_TOKEN)
    previous = Map.new(tracked, &{&1, System.get_env(&1)})
    Enum.each(tracked, &System.delete_env/1)

    on_exit(fn ->
      if previous_dir,
        do: System.put_env("SHADOWOPS_IMPORT_DIR", previous_dir),
        else: System.delete_env("SHADOWOPS_IMPORT_DIR")

      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)

      File.rm_rf(root)
    end)

    {:ok, root: root}
  end

  test "missing source is explicit and never invents readiness" do
    gmail = SourceRegistry.snapshot("gmail")
    assert gmail.status == "NOT_CONFIGURED"
    assert gmail.real_data == false
    assert gmail.secret_binding.state == "MISSING"
    assert gmail.error_code == "IMPORT_MISSING"
  end

  test "valid import evidence is normalized without exposing secret values", %{root: root} do
    secret = "super-secret-value-that-must-never-render"
    System.put_env("GITHUB_TOKEN", secret)

    File.write!(
      Path.join(root, "github.json"),
      Jason.encode!(%{
        "status" => "ready",
        "health" => "healthy",
        "adapter" => "github_connector_v1",
        "record_count" => 42,
        "last_sync" => "2026-08-24T21:00:00Z",
        "real_data" => true,
        "reachable" => true
      })
    )

    github = SourceRegistry.snapshot("github")
    rendered = inspect(github)

    assert github.status == "READY"
    assert github.record_count == 42
    assert github.secret_binding.state == "CONFIGURED"
    assert github.secret_binding.required == ["GITHUB_TOKEN"]
    assert github.secret_binding.configured == ["GITHUB_TOKEN"]
    refute rendered =~ secret
  end

  test "invalid JSON fails visibly", %{root: root} do
    File.write!(Path.join(root, "finance.json"), "not-json")
    finance = SourceRegistry.snapshot("finance")

    assert finance.status == "NOT_CONFIGURED"
    assert finance.error_code == "INVALID_JSON"
    assert finance.real_data == false
  end

  test "configured secret names return names only" do
    System.put_env("GITHUB_TOKEN", "hidden-token")
    names = SourceRegistry.configured_secret_names()

    assert "GITHUB_TOKEN" in names
    refute inspect(names) =~ "hidden-token"
  end
end
