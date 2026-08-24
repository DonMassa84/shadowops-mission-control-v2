defmodule ShadowOps.Social.FacebookCommunicationBalance do
  @moduledoc """
  Privacy-safe communication-balance classification for pseudonymized Facebook
  Messenger 1:1 aggregate metrics.

  The classifier describes observable message distribution only. It does not
  interpret attraction, interest, rejection, manipulation, attachment,
  personality, or motivation.
  """

  @source_env "SHADOWOPS_FACEBOOK_BALANCE_SOURCE"
  @minimum_messages 30
  @minimum_sessions 5
  @privacy_marker "PSEUDONYMIZED_AGGREGATE"
  @classifier_status "BALANCE_CLASSIFIER_READY"
  @statuses ~w(BALANCED WATCH OVERINVESTING INSUFFICIENT_DATA)
  @confidences ~w(LOW MEDIUM HIGH INSUFFICIENT)

  @ranking_contact_keys ~w(
    chat messages inbound outbound outbound_share_me sessions initiations_me
    initiations_other initiation_share_me followups_me_ge30m
    followups_other_ge30m median_response_seconds_me
    median_response_seconds_other p90_response_seconds_me
    p90_response_seconds_other category
  )

  @snapshot_contact_keys ~w(
    chat status confidence messages sessions outbound_share_me
    initiation_share_me followups_me followups_other active_signals
    reason_codes privacy direction early_signal response_context
  )

  @snapshot_keys ~w(
    status generated_at source_status source_sha256 source_commit counts
    sufficient_data_count proportions chats knowledge_aggregates privacy
  )

  @spec source_path() :: String.t()
  def source_path do
    case Application.fetch_env(:shadowops_core, :facebook_balance_source) do
      {:ok, path} when is_binary(path) and path != "" -> path
      _ -> nonempty_env(@source_env) || default_source()
    end
  end

  @spec build_file(Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def build_file(path, opts \\ []) do
    with {:ok, body} <- File.read(path),
         {:ok, ranking} <- Jason.decode(body),
         :ok <- validate_ranking(ranking),
         {:ok, result} <-
           build(ranking,
             generated_at: Keyword.get(opts, :generated_at),
             source_commit: Keyword.get(opts, :source_commit),
             source_sha256: sha256(body)
           ) do
      {:ok, result}
    else
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_json}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec build(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def build(ranking, opts \\ [])

  def build(ranking, opts) when is_map(ranking) do
    with :ok <- validate_ranking(ranking) do
      chats =
        ranking["contacts"]
        |> Enum.map(&classify/1)
        |> Enum.sort_by(& &1["chat"])

      counts = Map.new(@statuses, &{&1, Enum.count(chats, fn row -> row["status"] == &1 end)})
      sufficient = length(chats) - counts["INSUFFICIENT_DATA"]

      result = %{
        "status" => @classifier_status,
        "generated_at" => Keyword.get(opts, :generated_at) || now(),
        "source_status" => ranking["status"],
        "source_sha256" => Keyword.get(opts, :source_sha256),
        "source_commit" => Keyword.get(opts, :source_commit),
        "counts" => counts,
        "sufficient_data_count" => sufficient,
        "proportions" => proportions(counts, sufficient),
        "chats" => chats,
        "knowledge_aggregates" => knowledge_aggregates(counts, sufficient),
        "privacy" => privacy_contract()
      }

      {:ok, result}
    end
  end

  def build(_ranking, _opts), do: {:error, :invalid_ranking_contract}

  @spec classify(map()) :: map()
  def classify(row) when is_map(row) do
    messages = integer_metric(row, "messages")
    sessions = integer_metric(row, "sessions")
    outbound = numeric_metric(row, "outbound_share_me")
    initiation = numeric_metric(row, "initiation_share_me")
    followups_me = integer_metric(row, "followups_me_ge30m")
    followups_other = integer_metric(row, "followups_other_ge30m")

    signals = signals(outbound, initiation, followups_me, followups_other)
    me_count = Enum.count(signals, &(&1 in ~w(OUTBOUND_HIGH INITIATION_HIGH FOLLOWUP_HIGH)))
    other_count = Enum.count(signals, &String.ends_with?(&1, "_OTHER_HIGH"))
    sufficient? = messages >= @minimum_messages and sessions >= @minimum_sessions

    %{
      "chat" => row["chat"],
      "status" => status(sufficient?, me_count, other_count),
      "confidence" => confidence(sessions),
      "messages" => messages,
      "sessions" => sessions,
      "outbound_share_me" => outbound,
      "initiation_share_me" => initiation,
      "followups_me" => followups_me,
      "followups_other" => followups_other,
      "active_signals" => signals,
      "reason_codes" => reason_codes(signals, messages, sessions),
      "privacy" => @privacy_marker,
      "direction" => direction(me_count, other_count),
      "early_signal" => early_signal(sessions),
      "response_context" => %{
        "median_seconds_me" => nullable_numeric_metric(row, "median_response_seconds_me"),
        "median_seconds_other" => nullable_numeric_metric(row, "median_response_seconds_other"),
        "investment_signal" => false
      }
    }
  end

  @spec write_snapshot(map(), Path.t()) :: :ok | {:error, term()}
  def write_snapshot(snapshot, path) when is_map(snapshot) and is_binary(path) do
    with :ok <- validate_snapshot(snapshot),
         :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, encoded} <- Jason.encode(snapshot, pretty: true),
         :ok <- atomic_write(path, encoded <> "\n") do
      :ok
    end
  end

  @spec snapshot(Path.t()) :: {:ok, map()} | {:error, term()}
  def snapshot(path \\ source_path()) do
    with {:ok, body} <- File.read(path),
         {:ok, data} <- Jason.decode(body),
         :ok <- validate_snapshot(data) do
      {:ok, data}
    else
      {:error, :enoent} -> {:error, :missing}
      {:error, %Jason.DecodeError{}} -> {:error, :invalid_json}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec load(Path.t()) :: {:ok, map()}
  def load(path \\ source_path()) do
    case snapshot(path) do
      {:ok, data} -> {:ok, available_view(data, path)}
      {:error, reason} -> {:ok, unavailable_view(path, reason)}
    end
  end

  def changed?(path, previous_mtime), do: mtime(path) != previous_mtime

  defp validate_ranking(%{
         "status" => "CONTACT_RANKING_READY",
         "contacts" => contacts,
         "total_one_to_one_chats" => total,
         "privacy" => %{
           "raw_names" => false,
           "raw_messages" => false,
           "media" => false,
           "chat_ids_pseudonymous" => true
         }
       })
       when is_list(contacts) and is_integer(total) and total == length(contacts) do
    if Enum.all?(contacts, &valid_ranking_contact?/1),
      do: :ok,
      else: {:error, :privacy_gate_failed}
  end

  defp validate_ranking(_), do: {:error, :invalid_ranking_contract}

  defp valid_ranking_contact?(row) when is_map(row) do
    keys = Map.keys(row)

    Enum.all?(keys, &(&1 in @ranking_contact_keys)) and
      valid_chat?(row["chat"]) and
      nonnegative_integer?(row["messages"]) and
      nonnegative_integer?(row["sessions"]) and
      share?(row["outbound_share_me"]) and
      share?(row["initiation_share_me"]) and
      nonnegative_integer?(row["followups_me_ge30m"]) and
      nonnegative_integer?(row["followups_other_ge30m"]) and
      nullable_number?(row["median_response_seconds_me"]) and
      nullable_number?(row["median_response_seconds_other"])
  end

  defp valid_ranking_contact?(_), do: false

  defp validate_snapshot(snapshot) when is_map(snapshot) do
    with true <- Map.keys(snapshot) |> Enum.all?(&(&1 in @snapshot_keys)),
         @classifier_status <- snapshot["status"],
         true <- is_binary(snapshot["generated_at"]),
         "CONTACT_RANKING_READY" <- snapshot["source_status"],
         true <- valid_sha?(snapshot["source_sha256"]),
         true <- nullable_string?(snapshot["source_commit"]),
         true <- valid_counts?(snapshot["counts"]),
         true <- is_integer(snapshot["sufficient_data_count"]),
         true <- valid_proportions?(snapshot["proportions"]),
         true <- valid_knowledge?(snapshot["knowledge_aggregates"]),
         true <- snapshot["privacy"] == privacy_contract(),
         chats when is_list(chats) <- snapshot["chats"],
         true <- Enum.all?(chats, &valid_snapshot_contact?/1),
         true <- counts_match?(snapshot["counts"], chats) do
      :ok
    else
      _ -> {:error, :invalid_balance_contract}
    end
  end

  defp validate_snapshot(_), do: {:error, :invalid_balance_contract}

  defp valid_snapshot_contact?(row) when is_map(row) do
    Map.keys(row) |> Enum.all?(&(&1 in @snapshot_contact_keys)) and
      valid_chat?(row["chat"]) and
      row["status"] in @statuses and
      row["confidence"] in @confidences and
      nonnegative_integer?(row["messages"]) and
      nonnegative_integer?(row["sessions"]) and
      share?(row["outbound_share_me"]) and
      share?(row["initiation_share_me"]) and
      nonnegative_integer?(row["followups_me"]) and
      nonnegative_integer?(row["followups_other"]) and
      is_list(row["active_signals"]) and
      is_list(row["reason_codes"]) and
      row["privacy"] == @privacy_marker and
      row["direction"] in ~w(BALANCED ME_MORE COUNTERPART_MORE MIXED) and
      row["early_signal"] in ~w(NOT_ACTIVE EARLY_LOW_CONFIDENCE EARLY_MEDIUM_CONFIDENCE ESTABLISHED_HIGH_CONFIDENCE) and
      valid_response_context?(row["response_context"])
  end

  defp valid_snapshot_contact?(_), do: false

  defp signals(outbound, initiation, followups_me, followups_other) do
    []
    |> add_signal(outbound >= 0.60, "OUTBOUND_HIGH")
    |> add_signal(outbound <= 0.40, "OUTBOUND_OTHER_HIGH")
    |> add_signal(initiation >= 0.65, "INITIATION_HIGH")
    |> add_signal(initiation <= 0.35, "INITIATION_OTHER_HIGH")
    |> add_signal(followups_me >= max(4, followups_other * 1.75), "FOLLOWUP_HIGH")
    |> add_signal(followups_other >= max(4, followups_me * 1.75), "FOLLOWUP_OTHER_HIGH")
  end

  defp add_signal(signals, true, signal), do: signals ++ [signal]
  defp add_signal(signals, false, _signal), do: signals

  defp status(false, _me_count, _other_count), do: "INSUFFICIENT_DATA"

  defp status(true, me_count, other_count) when me_count >= 2 and me_count > other_count,
    do: "OVERINVESTING"

  defp status(true, 0, 0), do: "BALANCED"
  defp status(true, _me_count, _other_count), do: "WATCH"

  defp confidence(sessions) when sessions < 5, do: "INSUFFICIENT"
  defp confidence(sessions) when sessions < 10, do: "LOW"
  defp confidence(sessions) when sessions < 20, do: "MEDIUM"
  defp confidence(_sessions), do: "HIGH"

  defp early_signal(sessions) when sessions < 5, do: "NOT_ACTIVE"
  defp early_signal(sessions) when sessions < 10, do: "EARLY_LOW_CONFIDENCE"
  defp early_signal(sessions) when sessions < 20, do: "EARLY_MEDIUM_CONFIDENCE"
  defp early_signal(_sessions), do: "ESTABLISHED_HIGH_CONFIDENCE"

  defp direction(0, 0), do: "BALANCED"
  defp direction(me_count, other_count) when me_count > other_count, do: "ME_MORE"
  defp direction(me_count, other_count) when other_count > me_count, do: "COUNTERPART_MORE"
  defp direction(_me_count, _other_count), do: "MIXED"

  defp reason_codes(signals, messages, sessions) do
    insufficient =
      []
      |> add_reason(messages < @minimum_messages, "MESSAGES_BELOW_MINIMUM")
      |> add_reason(sessions < @minimum_sessions, "SESSIONS_BELOW_MINIMUM")

    dimensions = [
      reason_for_dimension(signals, "OUTBOUND"),
      reason_for_dimension(signals, "INITIATION"),
      reason_for_dimension(signals, "FOLLOWUP")
    ]

    insufficient ++ dimensions
  end

  defp add_reason(reasons, true, reason), do: reasons ++ [reason]
  defp add_reason(reasons, false, _reason), do: reasons

  defp reason_for_dimension(signals, dimension) do
    cond do
      "#{dimension}_HIGH" in signals -> "#{dimension}_HIGH"
      "#{dimension}_OTHER_HIGH" in signals -> "#{dimension}_OTHER_HIGH"
      true -> "#{dimension}_BALANCED"
    end
  end

  defp proportions(_counts, 0) do
    %{
      "balanced_share_sufficient" => nil,
      "watch_share_sufficient" => nil,
      "overinvesting_share_sufficient" => nil
    }
  end

  defp proportions(counts, sufficient) do
    %{
      "balanced_share_sufficient" => ratio(counts["BALANCED"], sufficient),
      "watch_share_sufficient" => ratio(counts["WATCH"], sufficient),
      "overinvesting_share_sufficient" => ratio(counts["OVERINVESTING"], sufficient)
    }
  end

  defp knowledge_aggregates(counts, sufficient) do
    %{
      "facebook_balance_balanced_count" => counts["BALANCED"],
      "facebook_balance_watch_count" => counts["WATCH"],
      "facebook_balance_overinvesting_count" => counts["OVERINVESTING"],
      "facebook_balance_sufficient_data_count" => sufficient
    }
  end

  defp privacy_contract do
    %{
      "classification" => @privacy_marker,
      "aggregate_only" => true,
      "raw_messages" => false,
      "raw_names" => false,
      "phones" => false,
      "emails" => false,
      "media" => false,
      "identity_maps" => false,
      "nlp_interpretation" => false
    }
  end

  defp available_view(data, path) do
    %{
      available?: true,
      ready?: true,
      status: data["status"],
      generated_at: data["generated_at"],
      source_sha256: data["source_sha256"],
      source_commit: data["source_commit"],
      counts: data["counts"],
      sufficient_data_count: data["sufficient_data_count"],
      proportions: data["proportions"],
      chats: data["chats"],
      knowledge_aggregates: data["knowledge_aggregates"],
      privacy: data["privacy"],
      source: source_view(path)
    }
  end

  defp unavailable_view(path, reason) do
    %{
      available?: false,
      ready?: false,
      status: "UNAVAILABLE",
      unavailable_reason: reason,
      generated_at: nil,
      source_sha256: nil,
      source_commit: nil,
      counts: %{},
      sufficient_data_count: nil,
      proportions: %{},
      chats: [],
      knowledge_aggregates: %{},
      privacy: privacy_contract(),
      source: source_view(path)
    }
  end

  defp source_view(path), do: %{path: path, mtime: mtime(path), sha256: file_sha256(path)}

  defp mtime(path) do
    case File.stat(path) do
      {:ok, stat} -> stat.mtime
      _ -> nil
    end
  end

  defp file_sha256(path) do
    case File.read(path) do
      {:ok, body} -> sha256(body)
      _ -> nil
    end
  end

  defp atomic_write(path, body) do
    temporary = path <> ".tmp-#{System.unique_integer([:positive])}"

    with :ok <- File.write(temporary, body, [:binary, :exclusive]),
         :ok <- File.chmod(temporary, 0o600),
         :ok <- File.rename(temporary, path) do
      :ok
    else
      {:error, _reason} = error ->
        File.rm(temporary)
        error
    end
  end

  defp valid_counts?(counts) when is_map(counts) do
    Map.keys(counts) |> Enum.sort() == Enum.sort(@statuses) and
      Enum.all?(counts, fn {_status, value} -> nonnegative_integer?(value) end)
  end

  defp valid_counts?(_), do: false

  defp counts_match?(counts, chats) do
    Enum.all?(@statuses, fn status ->
      counts[status] == Enum.count(chats, &(&1["status"] == status))
    end)
  end

  defp valid_proportions?(proportions) when is_map(proportions) do
    Enum.all?(proportions, fn {_key, value} -> is_nil(value) or share?(value) end)
  end

  defp valid_proportions?(_), do: false

  defp valid_knowledge?(knowledge) when is_map(knowledge) do
    Map.keys(knowledge) |> Enum.sort() ==
      Enum.sort(~w(
        facebook_balance_balanced_count facebook_balance_watch_count
        facebook_balance_overinvesting_count facebook_balance_sufficient_data_count
      )) and Enum.all?(knowledge, fn {_key, value} -> nonnegative_integer?(value) end)
  end

  defp valid_knowledge?(_), do: false

  defp valid_response_context?(%{
         "median_seconds_me" => me,
         "median_seconds_other" => other,
         "investment_signal" => false
       }),
       do: nullable_number?(me) and nullable_number?(other)

  defp valid_response_context?(_), do: false

  defp valid_chat?(value) when is_binary(value), do: Regex.match?(~r/^C_[0-9a-f]{16}$/, value)
  defp valid_chat?(_), do: false

  defp share?(value) when is_integer(value), do: value in 0..1
  defp share?(value) when is_float(value), do: value >= 0.0 and value <= 1.0
  defp share?(_), do: false

  defp nonnegative_integer?(value), do: is_integer(value) and value >= 0
  defp nullable_number?(nil), do: true
  defp nullable_number?(value), do: is_number(value) and value >= 0
  defp nullable_string?(nil), do: true
  defp nullable_string?(value), do: is_binary(value) and value != ""
  defp valid_sha?(value), do: is_binary(value) and Regex.match?(~r/^[0-9a-f]{64}$/, value)

  defp integer_metric(row, key), do: Map.get(row, key, 0)
  defp numeric_metric(row, key), do: Map.get(row, key, 0.0)
  defp nullable_numeric_metric(row, key), do: Map.get(row, key)
  defp ratio(value, total), do: Float.round(value / total, 4)
  defp sha256(body), do: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp default_source do
    home = System.user_home() || System.get_env("HOME") || "."
    Path.join(home, ".local/share/shadowops/facebook_balance.json")
  end

  defp nonempty_env(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end
end
