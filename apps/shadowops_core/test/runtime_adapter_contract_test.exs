defmodule ShadowOpsCore.RuntimeAdapterContractTest do
  use ExUnit.Case, async: false

  alias ShadowOpsCore.Adapters.{OllamaAdapter, OpenCodeAdapter}
  alias ShadowOpsCore.{CapabilityRegistry, RiskPolicy}

  setup do
    previous = %{
      opencode_bin: System.get_env("SHADOWOPS_OPENCODE_BIN"),
      opencode_roots: System.get_env("SHADOWOPS_OPENCODE_ALLOWED_ROOTS"),
      ollama_url: System.get_env("SHADOWOPS_OLLAMA_URL"),
      ollama_hosts: System.get_env("SHADOWOPS_OLLAMA_ALLOWED_HOSTS")
    }

    on_exit(fn ->
      restore_env("SHADOWOPS_OPENCODE_BIN", previous.opencode_bin)
      restore_env("SHADOWOPS_OPENCODE_ALLOWED_ROOTS", previous.opencode_roots)
      restore_env("SHADOWOPS_OLLAMA_URL", previous.ollama_url)
      restore_env("SHADOWOPS_OLLAMA_ALLOWED_HOSTS", previous.ollama_hosts)
    end)

    :ok
  end

  test "runtime capabilities are mapped to concrete governed executors" do
    assert {:ok, %{executor: :service_runtime}} = CapabilityRegistry.lookup("systemd.status")
    assert {:ok, %{executor: :service_runtime}} = CapabilityRegistry.lookup("systemd.restart")
    assert {:ok, %{executor: :opencode_runtime}} = CapabilityRegistry.lookup("opencode.execute")
    assert {:ok, %{executor: :not_connected}} = CapabilityRegistry.lookup("ollama.generate")

    assert RiskPolicy.infer_risk("systemd.status") == "L0"
    assert RiskPolicy.infer_risk("systemd.restart") == "L1"
    assert RiskPolicy.infer_risk("opencode.execute") == "L2"
    assert RiskPolicy.infer_risk("ollama.generate") == "L0"
  end

  test "OpenCode executes argv without a shell and enforces project roots" do
    root = temp_dir("opencode")
    executable = Path.join(root, "opencode")
    marker = Path.join(root, "must-not-exist")

    File.write!(
      executable,
      "#!/bin/sh\nprintf '%s\\n' \"$*\"\n"
    )

    File.chmod!(executable, 0o755)
    System.put_env("SHADOWOPS_OPENCODE_BIN", executable)
    System.put_env("SHADOWOPS_OPENCODE_ALLOWED_ROOTS", root)

    resource = %{executable: executable}
    prompt = "literal $(touch #{marker})"

    assert {:ok, result} =
             OpenCodeAdapter.run(
               resource,
               %{prompt: prompt, project_dir: root},
               %{policy_decision: "APPROVED"}
             )

    assert result.status == "COMPLETED"
    assert result.runtime == "opencode"
    assert result.real_data == true
    assert result.synthetic == false
    assert result.output =~ "run --format json"
    assert result.output =~ prompt
    refute File.exists?(marker)

    outside = System.tmp_dir!()

    if Path.expand(outside) != Path.expand(root) do
      assert {:error, :project_dir_not_allowlisted} =
               OpenCodeAdapter.run(
                 resource,
                 %{prompt: "safe", project_dir: outside},
                 %{policy_decision: "APPROVED"}
               )
    end

    assert {:error, :policy_decision_required} =
             OpenCodeAdapter.run(resource, %{prompt: "safe", project_dir: root}, %{})
  end

  test "Ollama rejects non-allowlisted endpoints without making a network request" do
    System.put_env("SHADOWOPS_OLLAMA_URL", "http://example.invalid:11434")
    System.put_env("SHADOWOPS_OLLAMA_ALLOWED_HOSTS", "127.0.0.1,localhost")

    assert %{
             state: "NOT_CONFIGURED",
             reachable: false,
             real_data: false,
             synthetic: false,
             reason: "ollama_host_not_allowlisted"
           } = OllamaAdapter.status()
  end

  test "Ollama model validation is bounded and stop remains policy-gated" do
    resource = %{name: "qwen2.5-coder:14b", base_url: "http://127.0.0.1:11434"}

    assert :ok = OllamaAdapter.validate(resource)

    assert {:error, :invalid_model} =
             OllamaAdapter.validate(%{resource | name: "bad model; rm -rf /"})

    assert {:error, :policy_decision_required} = OllamaAdapter.stop(resource, %{})
  end

  defp temp_dir(prefix) do
    path =
      Path.join(
        System.tmp_dir!(),
        "shadowops-#{prefix}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
