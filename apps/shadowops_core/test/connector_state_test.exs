defmodule ShadowOpsCore.ConnectorStateTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.ConnectorState

  test "accepts a positive state only with live real evidence" do
    assert {:ok, state} =
             ConnectorState.new(%{
               id: "real",
               name: "Real",
               kind: "test",
               status: "CONNECTED",
               health: "HEALTHY",
               source: "/tmp/source",
               source_type: "LIVE",
               real_data: true,
               synthetic: false,
               enabled: true,
               reachable: true,
               record_count: 1
             })

    assert state.status == "READY"
  end

  test "synthetic data and historical sources can never become positive" do
    base = %{
      id: "unsafe",
      name: "Unsafe",
      kind: "test",
      status: "ONLINE",
      health: "HEALTHY",
      source: "/tmp/source",
      source_type: "LIVE",
      real_data: true,
      synthetic: false,
      enabled: true,
      reachable: true
    }

    assert {:error, :synthetic_source_cannot_be_positive} =
             ConnectorState.new(%{base | synthetic: true})

    assert {:error, :non_live_source_cannot_be_positive} =
             ConnectorState.new(%{base | source_type: "HISTORICAL"})
  end

  test "malformed counts fail closed and every required failure state is accepted" do
    assert ConnectorState.build(%{id: "bad", record_count: "12"}).status == "UNKNOWN"

    for status <- ~w(DEGRADED UNAVAILABLE UNKNOWN CONFIGURATION_REQUIRED OPTIONAL_UNAVAILABLE) do
      assert {:ok, state} =
               ConnectorState.new(%{
                 id: String.downcase(status),
                 name: status,
                 kind: "test",
                 status: status,
                 health: status,
                 source: nil,
                 source_type: "UNKNOWN",
                 real_data: false,
                 synthetic: false,
                 enabled: true,
                 reachable: false
               })

      assert state.status == status
    end
  end

  test "normalizes legacy transport labels before they reach API or UI" do
    base = %{
      id: "legacy",
      name: "Legacy",
      kind: "test",
      health: "HEALTHY",
      source: "/tmp/source",
      source_type: "LIVE",
      real_data: true,
      synthetic: false,
      enabled: true,
      reachable: true
    }

    for status <- ~w(CONNECTED ONLINE) do
      assert {:ok, %{status: "READY"}} = ConnectorState.new(Map.put(base, :status, status))
    end

    assert {:ok, %{status: "UNAVAILABLE"}} =
             ConnectorState.new(Map.merge(base, %{status: "NOT_CONNECTED", reachable: false}))
  end
end
