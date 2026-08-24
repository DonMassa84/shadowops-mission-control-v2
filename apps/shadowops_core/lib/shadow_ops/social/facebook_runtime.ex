defmodule ShadowOps.Social.FacebookRuntime do
  @moduledoc """
  Privacy-safe adapter for the real local Facebook aggregate runtime snapshot.

  The accepted contract explicitly excludes raw messages, identities, media,
  credentials and per-contact records. Invalid or incomplete snapshots fail
  closed without returning any source payload.
  """

  @source_env "SHADOWOPS_FACEBOOK_RUNTIME_SOURCE"
  @forbidden_top_level_keys ~w(contacts top_one_to_one_chats top_group_chats)

  def source_path do
    case Application.fetch_env(:shadowops_core, :facebook_runtime_source) do
      {:ok, path} when is_binary(path) and path != "" -> path
      _ -> nonempty_env(@source_env) || default_source()
    end
  end

  def load(path \\ source_path()) do
    case File.read(path) do
      {:ok, body} -> decode(body, path)
      {:error, :enoent} -> {:ok, unavailable(path, :missing)}
      {:error, reason} -> {:ok, unavailable(path, {:source_unreadable, reason})}
    end
  end

  def changed?(path, previous_mtime), do: mtime(path) != previous_mtime

  defp decode(body, path) do
    with {:ok, data} <- Jason.decode(body),
         :ok <- validate(data) do
      {:ok, build_view(data, path)}
    else
      {:error, %Jason.DecodeError{}} -> {:ok, unavailable(path, :invalid_json)}
      {:error, reason} -> {:ok, unavailable(path, reason)}
    end
  end

  defp validate(
         %{
           "status" => "FACEBOOK_RUNTIME_READY",
           "metrics_status" => "FACEBOOK_METRICS_READY",
           "ranking_status" => "CONTACT_RANKING_READY",
           "privacy" => %{
             "aggregate_only" => true,
             "raw_messages" => false,
             "raw_names" => false,
             "media" => false,
             "contact_records" => false
           },
           "one_to_one" => one_to_one,
           "all_chats" => all_chats,
           "categories" => categories
         } = data
       )
       when is_map(one_to_one) and is_map(all_chats) and is_map(categories) do
    cond do
      Enum.any?(@forbidden_top_level_keys, &Map.has_key?(data, &1)) ->
        {:error, :privacy_contract_violation}

      positive_integer?(one_to_one["messages"]) and positive_integer?(one_to_one["chats"]) and
        positive_integer?(all_chats["messages"]) and positive_integer?(all_chats["chats"]) ->
        :ok

      true ->
        {:error, :empty_runtime_dataset}
    end
  end

  defp validate(_), do: {:error, :invalid_runtime_contract}

  defp build_view(data, path) do
    one = data["one_to_one"]
    all = data["all_chats"]

    %{
      available?: true,
      ready?: true,
      status: "READY",
      pipeline_status: data["metrics_status"],
      ranking_status: data["ranking_status"],
      privacy_status: "PROTECTED",
      generated_at: data["generated_at"],
      source_commit: data["source_commit"],
      source: source_view(path),
      metrics: %{
        "TOTAL MESSAGES" => all["messages"],
        "TOTAL CHATS" => all["chats"],
        "1:1 MESSAGES" => one["messages"],
        "1:1 CHATS" => one["chats"],
        "INBOUND" => one["inbound"],
        "OUTBOUND" => one["outbound"],
        "RECIPROCITY" => one["reciprocity_balance"],
        "INITIATION SHARE ME" => one["initiation_share_me"],
        "RESPONSE ME MEDIAN S" => one["median_response_seconds_me"],
        "RESPONSE OTHER MEDIAN S" => one["median_response_seconds_other"],
        "FOLLOW-UPS ME" => one["followups_without_direction_change_ge30m_me"],
        "FOLLOW-UPS OTHER" => one["followups_without_direction_change_ge30m_other"]
      },
      categories: data["categories"],
      total_one_to_one_chats: data["total_one_to_one_chats"],
      yearly_one_to_one: safe_list(data["yearly_one_to_one"])
    }
  end

  defp unavailable(path, reason) do
    %{
      available?: false,
      ready?: false,
      status: "UNAVAILABLE",
      unavailable_reason: reason,
      pipeline_status: "NOT_AVAILABLE",
      ranking_status: "NOT_AVAILABLE",
      privacy_status: "PROTECTED",
      generated_at: nil,
      source_commit: nil,
      source: source_view(path),
      metrics: %{},
      categories: %{},
      total_one_to_one_chats: nil,
      yearly_one_to_one: []
    }
  end

  defp source_view(path), do: %{path: path, mtime: mtime(path), sha256: sha256(path)}

  defp mtime(path) do
    case File.stat(path) do
      {:ok, stat} -> stat.mtime
      _ -> nil
    end
  end

  defp sha256(path) do
    case File.read(path) do
      {:ok, body} -> :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
      _ -> nil
    end
  end

  defp default_source do
    home = System.user_home() || System.get_env("HOME") || "."
    Path.join(home, ".local/share/shadowops/facebook_runtime.json")
  end

  defp nonempty_env(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp safe_list(value) when is_list(value), do: value
  defp safe_list(_), do: []
end
