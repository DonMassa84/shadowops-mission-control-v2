defmodule ShadowOpsCore.I7RemoteExecutor do
  @moduledoc """
  Strictly allow-listed SSH executor for CPU-bound QA work on the i7 node.

  No caller-provided shell fragment, executable path, host, systemd unit, port or
  arbitrary argument is accepted. The remote side executes a fixed wrapper with
  a validated job enum and exact Git SHA only.
  """

  @target "shadowserver-i7"
  @runner "$HOME/.local/bin/shadowops-i7-executor"
  @jobs ~w(cpu_probe format compile target_test full_test qa_bundle diff_check)a
  @sha_re ~r/\A[0-9a-f]{40}\z/

  def allowed_jobs, do: @jobs

  def execute(job, expected_sha) when job in @jobs and is_binary(expected_sha) do
    with :ok <- validate_sha(expected_sha) do
      started = System.monotonic_time(:millisecond)
      args = ssh_args(job, expected_sha)

      {output, code} = System.cmd("ssh", args, stderr_to_stdout: true)

      result = %{
        node_id: "i7",
        job: Atom.to_string(job),
        expected_sha: expected_sha,
        exit_code: code,
        output_sha256: sha256(output),
        duration_ms: elapsed(started),
        bounded: true,
        arbitrary_shell: false,
        arbitrary_systemd: false,
        production_mutation: false
      }

      if code == 0 and String.contains?(output, "I7_EXECUTOR=PASS") do
        {:ok, Map.put(result, :status, "PASS")}
      else
        {:error, Map.put(result, :status, "FAIL")}
      end
    end
  rescue
    error ->
      {:error,
       %{
         node_id: "i7",
         job: to_string(job),
         expected_sha: expected_sha,
         status: "FAIL",
         error: Exception.message(error),
         bounded: true,
         arbitrary_shell: false,
         arbitrary_systemd: false,
         production_mutation: false
       }}
  end

  def execute(_job, _expected_sha), do: {:error, :job_not_allowlisted}

  @doc false
  def ssh_args(job, expected_sha) when job in @jobs and is_binary(expected_sha) do
    [
      "-o",
      "BatchMode=yes",
      "-o",
      "ConnectTimeout=5",
      "-o",
      "ServerAliveInterval=5",
      "-o",
      "ServerAliveCountMax=2",
      @target,
      @runner,
      Atom.to_string(job),
      expected_sha
    ]
  end

  defp validate_sha(expected_sha) do
    if Regex.match?(@sha_re, expected_sha), do: :ok, else: {:error, :invalid_expected_sha}
  end

  defp sha256(output) do
    :crypto.hash(:sha256, output)
    |> Base.encode16(case: :lower)
  end

  defp elapsed(started), do: max(System.monotonic_time(:millisecond) - started, 0)
end
