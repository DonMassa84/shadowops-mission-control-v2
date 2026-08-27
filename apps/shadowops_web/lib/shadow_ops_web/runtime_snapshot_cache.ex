defmodule ShadowOpsWeb.RuntimeSnapshotCache do
  @moduledoc """
  Short-lived supervised cache for bounded runtime projections.

  Stable projections are cached for the normal TTL. Transient runtime
  failures remain visible to the caller but are not persisted as factual
  cached state.

  `fetch/3` supports an optional cache policy so callers such as
  RuntimeOverview can explicitly decide whether a projection is suitable
  for caching.
  """

  use GenServer

  @ttl_ms 10_000
  @call_timeout_ms 7_000

  @transient_error_codes ~w(
    SOURCE_TIMEOUT
    SOURCE_ERROR
    SOURCE_INVALID
  )

  def start_link(_opts),
    do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def fetch(key, builder) when is_function(builder, 0),
    do: fetch(key, builder, [])

  def fetch(key, builder, opts)
      when is_function(builder, 0) and is_list(opts) do
    GenServer.call(
      __MODULE__,
      {:fetch, key, builder, opts},
      @call_timeout_ms
    )
  end

  def fetch(key, builder, cache_if)
      when is_function(builder, 0) and is_function(cache_if, 1) do
    GenServer.call(
      __MODULE__,
      {:fetch, key, builder, cache_if},
      @call_timeout_ms
    )
  end

  def clear,
    do: GenServer.call(__MODULE__, :clear)

  @impl true
  def init(_opts),
    do: {:ok, %{entries: %{}}}

  @impl true
  def handle_call({:fetch, key, builder, policy}, _from, state) do
    now = System.monotonic_time(:millisecond)

    case Map.get(state.entries, key) do
      %{inserted_at: inserted_at, value: value}
      when now - inserted_at < @ttl_ms ->
        {:reply, value, state}

      _ ->
        value = builder.()

        if cacheable?(value, policy) do
          entry = %{
            inserted_at: System.monotonic_time(:millisecond),
            value: value
          }

          {:reply, value, put_in(state, [:entries, key], entry)}
        else
          {:reply, value, state}
        end
    end
  end

  @impl true
  def handle_call(:clear, _from, state),
    do: {:reply, :ok, %{state | entries: %{}}}

  defp cacheable?(value, policy) do
    policy_allows_cache?(value, policy) and
      not transient_failure?(value)
  end

  defp policy_allows_cache?(value, policy)
       when is_function(policy, 1) do
    safe_policy(policy, value)
  end

  defp policy_allows_cache?(value, opts)
       when is_list(opts) do
    policy =
      Keyword.get(opts, :cache_if) ||
        Keyword.get(opts, :cacheable?) ||
        Keyword.get(opts, :cache?)

    case policy do
      nil ->
        true

      fun when is_function(fun, 1) ->
        safe_policy(fun, value)

      true ->
        true

      false ->
        false

      _ ->
        false
    end
  end

  defp safe_policy(fun, value) do
    fun.(value) == true
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  defp transient_failure?(value) when is_map(value) do
    code =
      Map.get(value, :error_code) ||
        Map.get(value, "error_code")

    code in @transient_error_codes ||
      Enum.any?(Map.values(value), &transient_failure?/1)
  end

  defp transient_failure?(value) when is_list(value),
    do: Enum.any?(value, &transient_failure?/1)

  defp transient_failure?(_value),
    do: false
end
