defmodule ShadowOpsWeb.I7RotationAssetTest do
  use ExUnit.Case, async: true

  test "weighted selector passes deterministic Node regression suite" do
    test_file = Path.expand("i7_rotation_test.js", __DIR__)
    {output, status} = System.cmd("node", ["--test", test_file], stderr_to_stdout: true)
    assert status == 0, output
    assert output =~ ~r/# pass [1-9][0-9]*/
    assert output =~ "fail 0"
  end
end
