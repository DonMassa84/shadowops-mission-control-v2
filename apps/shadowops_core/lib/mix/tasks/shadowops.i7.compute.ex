defmodule Mix.Tasks.Shadowops.I7.Compute do
  use Mix.Task

  alias ShadowOpsCore.NodeComputeDispatcher

  @shortdoc "Run one allow-listed QA/compute job on the verified i7 node"
  @jobs ~w(cpu_probe format compile target_test full_test qa_bundle diff_check)

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, invalid} =
      OptionParser.parse(args, strict: [sha: :string], aliases: [s: :sha])

    case {positional, invalid, opts[:sha]} do
      {[job], [], sha} when job in @jobs and is_binary(sha) ->
        execute(String.to_existing_atom(job), sha)

      _ ->
        Mix.raise("usage: mix shadowops.i7.compute <#{Enum.join(@jobs, "|")}> --sha <40-hex-sha>")
    end
  end

  defp execute(job, sha) do
    case NodeComputeDispatcher.dispatch(job, sha, %{risk_level: "L0"}) do
      {:ok, %{route: route, execution: execution}} ->
        Mix.shell().info("I7_COMPUTE=PASS")
        Mix.shell().info("NODE=#{route.node_id}")
        Mix.shell().info("CAPABILITY=#{route.capability}")
        Mix.shell().info("JOB=#{execution.job}")
        Mix.shell().info("EXPECTED_SHA=#{execution.expected_sha}")
        Mix.shell().info("EXIT_CODE=#{execution.exit_code}")
        Mix.shell().info("OUTPUT_SHA256=#{execution.output_sha256}")
        Mix.shell().info("DURATION_MS=#{execution.duration_ms}")
        Mix.shell().info("4013_MUTATION=NO")
        Mix.shell().info("4014_MUTATION=NO")

      {:error, reason} ->
        Mix.raise("I7_COMPUTE=BLOCKED reason=#{inspect(reason)}")
    end
  end
end
