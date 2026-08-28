defmodule ShadowOpsCore.I7NodeTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.I7Node

  test "current real evidence activates QA and supplementary compute capabilities" do
    output = """
    hostname=shadowserver-i7
    cpus=8
    mix=1
    git=1
    workspace=1
    """

    node = I7Node.from_probe({output, 0}, 11)

    assert node.node_id == "i7"
    assert node.hostname == "shadowserver-i7"
    assert node.status == "READY"
    assert node.reachable
    assert node.real_data
    refute node.synthetic
    assert node.metadata.cpu_count == 8
    assert node.metadata.verified_capabilities == [
             "supplementary_compute",
             "repository_change",
             "qa"
           ]
    refute node.metadata.arbitrary_shell
    refute node.metadata.arbitrary_systemd
    refute node.metadata.production_control_plane
  end

  test "CPU-only evidence enables supplementary compute but not repository QA" do
    output = """
    hostname=shadowserver-i7
    cpus=8
    mix=0
    git=0
    workspace=0
    """

    node = I7Node.from_probe({output, 0}, 9)

    assert node.status == "READY"
    assert node.metadata.verified_capabilities == ["supplementary_compute"]
  end

  test "unreachable or invalid identity evidence never reports READY" do
    unreachable = I7Node.from_probe({"ssh failed", 255}, 5)
    invalid = I7Node.from_probe({"hostname=\ncpus=0\nmix=1\ngit=1\nworkspace=1\n", 0}, 4)

    for node <- [unreachable, invalid] do
      assert node.status == "OPTIONAL_UNAVAILABLE"
      refute node.reachable
      refute node.real_data
      assert node.metadata.verified_capabilities == []
    end
  end
end
