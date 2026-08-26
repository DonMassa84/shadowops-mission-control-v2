defmodule ShadowOpsCore.RemoteAIPolicyTest do
  use ExUnit.Case, async: false

  alias ShadowOpsCore.{CapabilityRegistry, GovernanceGate, Policy}

  test "local Ollama inference is disconnected and denied by policy" do
    assert {:ok, capability} = CapabilityRegistry.lookup("ollama.generate")
    assert capability.executor == :not_connected

    assert {:error, :local_ai_forbidden} = Policy.evaluate("ollama.generate", "operator-a")
    assert {:error, :local_ai_forbidden} = Policy.evaluate_action("ollama.generate")

    assert {:error, :local_ai_forbidden} =
             GovernanceGate.authorize(
               "ollama.generate",
               "operator-a",
               "local-model",
               %{prompt: "synthetic test prompt"},
               %{}
             )
  end
end
