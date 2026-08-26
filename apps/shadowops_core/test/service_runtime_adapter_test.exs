defmodule ShadowOpsCore.ServiceRuntimeAdapterTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.{ServiceRuntimeCorrelation, IntegrationProbe}
  alias ShadowOpsCore.Adapters.{ServiceRuntimeAdapter, SystemctlServiceRuntime}

  describe "ServiceRuntimeAdapter behaviour" do
    test "defines required callbacks" do
      callbacks = ServiceRuntimeAdapter.behaviour_info(:callbacks)
      assert {:services, 0} in callbacks
      assert {:service, 1} in callbacks
      assert {:runtime_identity, 1} in callbacks
    end
  end

  describe "IntegrationProbe behaviour" do
    test "defines probe callback" do
      callbacks = IntegrationProbe.behaviour_info(:callbacks)
      assert {:probe, 1} in callbacks
    end
  end

  describe "SystemctlServiceRuntime" do
    test "services/0 returns list or empty" do
      result = SystemctlServiceRuntime.services()
      assert {:ok, services} = result
      assert is_list(services)
    end

    test "service/1 with invalid identity returns not_found" do
      assert {:error, :not_found} = SystemctlServiceRuntime.service("invalid:nonexistent")
    end

    test "runtime_identity/1 with invalid identity returns not_found" do
      assert {:error, :not_found} =
               SystemctlServiceRuntime.runtime_identity("invalid:nonexistent")
    end
  end

  describe "ServiceRuntimeCorrelation (pure, no runtime IO)" do
    test "correlate with non-existent service in an empty snapshot returns discovered" do
      candidate = %{name: "nonexistent.service", scope: "user"}

      {:ok, result} = ServiceRuntimeCorrelation.correlate(candidate, [])

      assert result.status == "DISCOVERED"
      assert result.runtime_verified == false
      assert result.runtime_conflict == false
      assert result.runtime_ambiguous == false
    end

    test "correlate with a matching runtime snapshot returns runtime_verified when fragment present" do
      runtime = [
        %{
          scope: "user",
          name: "shadowops-phoenix.service",
          active_state: "active",
          fragment_path: "/home/schattenmacher/.config/systemd/user/shadowops-phoenix.service",
          source_path: nil,
          runtime_verified: true
        }
      ]

      candidate = %{name: "shadowops-phoenix.service", scope: "user"}

      {:ok, result} = ServiceRuntimeCorrelation.correlate(candidate, runtime)

      assert result.runtime_verified == true
      assert result.status == "RUNTIME_VERIFIED"
      assert result.live == true
      assert result.identity == "user:shadowops-phoenix.service"
    end

    test "active-only without fragment path is NOT runtime_verified" do
      runtime = [
        %{
          scope: "system",
          name: "nginx.service",
          active_state: "active",
          fragment_path: nil,
          source_path: nil,
          runtime_verified: false
        }
      ]

      candidate = %{name: "nginx.service", scope: "system"}

      {:ok, result} = ServiceRuntimeCorrelation.correlate(candidate, runtime)

      # active-only must NOT yield runtime_verified / READY
      assert result.runtime_verified == false
      assert result.status == "DISCOVERED"
    end

    test "ambiguous match (duplicate scope:name) fails closed" do
      runtime = [
        %{
          scope: "user",
          name: "dupe.service",
          active_state: "active",
          fragment_path: nil,
          runtime_verified: false
        },
        %{
          scope: "user",
          name: "dupe.service",
          active_state: "active",
          fragment_path: nil,
          runtime_verified: false
        }
      ]

      candidate = %{name: "dupe.service", scope: "user"}

      {:ok, result} = ServiceRuntimeCorrelation.correlate(candidate, runtime)

      assert result.runtime_ambiguous == true
      assert result.runtime_verified == false
    end

    test "mismatched scope fails closed to discovered" do
      runtime = [
        %{
          scope: "system",
          name: "x.service",
          active_state: "active",
          fragment_path: nil,
          runtime_verified: false
        }
      ]

      candidate = %{name: "x.service", scope: "user"}

      {:ok, result} = ServiceRuntimeCorrelation.correlate(candidate, runtime)

      assert result.status == "DISCOVERED"
      assert result.runtime_verified == false
    end

    test "correlate performs zero adapter/systemctl calls (pure)" do
      # If this function were to call adapter.services(), passing a plain list
      # would raise (no such function). Returning a result proves no IO occurred.
      runtime = [
        %{
          scope: "user",
          name: "pure.service",
          active_state: "inactive",
          fragment_path: nil,
          runtime_verified: false
        }
      ]

      candidate = %{name: "pure.service", scope: "user"}
      {:ok, result} = ServiceRuntimeCorrelation.correlate(candidate, runtime)
      assert result.status == "DISCOVERED"
    end
  end

  describe "classify_health returns correct health state" do
    test "synthetic and unverified" do
      assert :discovered = ServiceRuntimeCorrelation.classify_health(%{synthetic: true})
      assert :discovered = ServiceRuntimeCorrelation.classify_health(%{runtime_verified: false})
    end

    test "progression" do
      assert :runtime_verified =
               ServiceRuntimeCorrelation.classify_health(%{runtime_verified: true, live: false})

      assert :live =
               ServiceRuntimeCorrelation.classify_health(%{
                 runtime_verified: true,
                 live: true,
                 connected: false
               })

      assert :connected =
               ServiceRuntimeCorrelation.classify_health(%{
                 runtime_verified: true,
                 live: true,
                 connected: true,
                 real_data: false
               })

      assert :real_data =
               ServiceRuntimeCorrelation.classify_health(%{
                 runtime_verified: true,
                 live: true,
                 connected: true,
                 real_data: true,
                 governance_mapped: false
               })

      assert :ready =
               ServiceRuntimeCorrelation.classify_health(%{
                 runtime_verified: true,
                 live: true,
                 connected: true,
                 real_data: true,
                 governance_mapped: true,
                 runtime_conflict: false,
                 runtime_ambiguous: false
               })
    end

    test "conflict prevents READY" do
      result = %{
        runtime_verified: true,
        live: true,
        connected: true,
        real_data: true,
        governance_mapped: true,
        runtime_conflict: true,
        runtime_ambiguous: false
      }

      assert :conflict = ServiceRuntimeCorrelation.classify_health(result)
    end

    test "ambiguity prevents READY" do
      result = %{
        runtime_verified: true,
        live: true,
        connected: true,
        real_data: true,
        governance_mapped: true,
        runtime_conflict: false,
        runtime_ambiguous: true
      }

      assert :ambiguous = ServiceRuntimeCorrelation.classify_health(result)
    end

    test "synthetic data prevents READY" do
      result = %{
        synthetic: true,
        runtime_verified: true,
        live: true,
        connected: true,
        real_data: true,
        governance_mapped: true
      }

      assert :discovered = ServiceRuntimeCorrelation.classify_health(result)
    end
  end
end
