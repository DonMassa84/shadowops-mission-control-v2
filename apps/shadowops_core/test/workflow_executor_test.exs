defmodule ShadowOpsCore.WorkflowExecutorTest do
  use ExUnit.Case, async: true

  alias ShadowOpsCore.WorkflowExecutor

  test "passes shell metacharacters as literal argv without shell evaluation" do
    runtime = System.find_executable("printf")
    assert is_binary(runtime)

    workflow = %{"runtime" => runtime, "status" => "active"}

    arguments = [
      ";",
      "&&",
      "||",
      "$(printf exploited)",
      "`printf exploited`",
      "left | right",
      "left > right",
      "two words",
      "\"quoted value\""
    ]

    Enum.each(arguments, fn argument ->
      assert {:ok, %{exit_code: 0, summary: "[" <> output}} =
               WorkflowExecutor.execute(workflow, %{"args" => ["[%s]", argument]})

      assert output == argument <> "]"
    end)

    marker =
      Path.join(
        System.tmp_dir!(),
        "shadowops-executor-marker-#{System.unique_integer([:positive])}"
      )

    payload = "$(touch #{marker})"

    assert {:ok, %{summary: ^payload, exit_code: 0}} =
             WorkflowExecutor.execute(workflow, %{"args" => ["%s", payload]})

    refute File.exists?(marker)
  end

  test "runtime selection comes from the trusted workflow and ignores input runtime fields" do
    runtime = System.find_executable("printf")
    false_runtime = System.find_executable("false")
    assert is_binary(runtime) and is_binary(false_runtime)

    workflow = %{"runtime" => runtime, "status" => "active"}

    assert {:ok, %{summary: "registry runtime", exit_code: 0}} =
             WorkflowExecutor.execute(workflow, %{
               "runtime" => false_runtime,
               "args" => ["%s", "registry runtime"]
             })
  end

  test "registry argv overrides request argv" do
    runtime = System.find_executable("printf")
    assert is_binary(runtime)

    workflow = %{
      "runtime" => runtime,
      "status" => "VERIFIED_EXECUTABLE",
      "argv" => ["%s", "registry argv"]
    }

    assert {:ok, %{summary: "registry argv", exit_code: 0}} =
             WorkflowExecutor.execute(workflow, %{
               "runtime" => System.find_executable("false"),
               "args" => ["%s", "request argv"]
             })
  end

  test "malformed registry argv fails closed instead of using request argv" do
    runtime = System.find_executable("printf")
    assert is_binary(runtime)

    workflow = %{
      "runtime" => runtime,
      "status" => "VERIFIED_EXECUTABLE",
      "argv" => ["%s", 42]
    }

    assert {:error, %{summary: ":invalid_arguments", exit_code: nil}} =
             WorkflowExecutor.execute(workflow, %{"args" => ["%s", "request argv"]})
  end

  test "registry shell metacharacters remain literal argv" do
    runtime = System.find_executable("printf")
    assert is_binary(runtime)

    marker =
      Path.join(
        System.tmp_dir!(),
        "shadowops-registry-argv-marker-#{System.unique_integer([:positive])}"
      )

    payload = "$(touch #{marker})"

    workflow = %{
      "runtime" => runtime,
      "status" => "VERIFIED_EXECUTABLE",
      "argv" => ["%s", payload]
    }

    assert {:ok, %{summary: ^payload, exit_code: 0}} =
             WorkflowExecutor.execute(workflow, %{"args" => ["ignored"]})

    refute File.exists?(marker)
  end
end
