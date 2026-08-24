defmodule Mix.Tasks.Shadowops.Facebook.Balance do
  @shortdoc "Builds the privacy-safe Facebook communication-balance snapshot"

  @moduledoc """
  Builds a local, pseudonymized aggregate snapshot from the existing Facebook
  contact-ranking report.

      mix shadowops.facebook.balance \
        --source /path/to/facebook_contact_ranking.json \
        --output /path/to/facebook_balance.json \
        --source-commit COMMIT_SHA

  No raw exports are accepted by this task.
  """

  use Mix.Task

  alias ShadowOps.Social.FacebookCommunicationBalance

  @switches [source: :string, output: :string, source_commit: :string, generated_at: :string]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches)

    if positional != [] or invalid != [] do
      Mix.raise("unexpected arguments: #{inspect(positional ++ invalid)}")
    end

    source = opts[:source] || Mix.raise("--source is required")
    output = opts[:output] || FacebookCommunicationBalance.source_path()

    build_opts =
      [
        source_commit: opts[:source_commit],
        generated_at: opts[:generated_at]
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    with {:ok, snapshot} <- FacebookCommunicationBalance.build_file(source, build_opts),
         :ok <- deterministic_gate(source, build_opts, snapshot),
         :ok <- FacebookCommunicationBalance.write_snapshot(snapshot, output),
         {:ok, persisted} <- FacebookCommunicationBalance.snapshot(output),
         true <- persisted == snapshot do
      Mix.shell().info("BALANCE_CLASSIFIER_READY")
      Mix.shell().info("BALANCE_PRIVACY_GATE=PASS")
      Mix.shell().info("BALANCE_DETERMINISM=PASS")
      Mix.shell().info("BALANCE_EARLY_SIGNAL=PASS")
      Mix.shell().info("BALANCE_OUTPUT=#{output}")
    else
      false -> Mix.raise("persisted balance snapshot differs from generated snapshot")
      {:error, reason} -> Mix.raise("Facebook balance build failed: #{inspect(reason)}")
    end
  end

  defp deterministic_gate(source, opts, expected) do
    fixed_opts = Keyword.put(opts, :generated_at, expected["generated_at"])

    case FacebookCommunicationBalance.build_file(source, fixed_opts) do
      {:ok, ^expected} -> :ok
      {:ok, _different} -> {:error, :nondeterministic_output}
      {:error, reason} -> {:error, reason}
    end
  end
end
