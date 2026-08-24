defmodule ShadowOpsWeb.RuntimeSnapshotCache do
  @moduledoc "Short-lived supervised cache for bounded runtime projections."
  use GenServer

  @ttl_ms 10_000
  @call_timeout_ms 7_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def fetch(key, builder) when is_function(builder, 0) do
    GenServer.call(__MODULE__, {:fetch, key, builder}, @call_timeout_ms)
  end

  def clear, do: GenServer.call(__MODULE__, :clear)

  @impl true
  def init(_opts), do: {:ok, %{entries: %{}}}

  @impl true
  def handle_call({:fetch, key, builder}, _from, state) do
    now = System.monotonic_time(:millisecond)

    case Map.get(state.entries, key) do
      %{inserted_at: inserted_at, value: value} when now - inserted_at < @ttl_ms ->
        {:reply, value, state}

      _ ->
        value = builder.()
        entry = %{inserted_at: System.monotonic_time(:millisecond), value: value}
        {:reply, value, put_in(state, [:entries, key], entry)}
    end
  end

  def handle_call(:clear, _from, state), do: {:reply, :ok, %{state | entries: %{}}}
end
