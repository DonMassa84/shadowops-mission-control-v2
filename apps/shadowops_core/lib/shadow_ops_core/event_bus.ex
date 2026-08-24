defmodule ShadowOpsCore.EventBus do
  @moduledoc "Bounded in-memory canonical event bus; durable actions remain in the audit hash chain."
  use GenServer

  alias ShadowOpsCore.CanonicalEvent

  @max_events 1_000

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def publish(attrs) when is_map(attrs) do
    with {:ok, event} <- CanonicalEvent.new(attrs),
         {:ok, published} <- GenServer.call(__MODULE__, {:publish, event}) do
      {:ok, published}
    end
  end

  def list(filters \\ %{}), do: GenServer.call(__MODULE__, {:list, filters})
  def reset, do: GenServer.call(__MODULE__, :reset)

  @impl true
  def init(_opts), do: {:ok, []}

  @impl true
  def handle_call({:publish, event}, _from, events) do
    events = [event | events] |> Enum.take(@max_events)
    {:reply, {:ok, event}, events}
  end

  def handle_call({:list, filters}, _from, events) do
    filtered =
      Enum.filter(events, fn event ->
        Enum.all?(filters, fn {key, expected} ->
          Map.get(event, normalize_key(key)) == expected
        end)
      end)

    {:reply, filtered, events}
  end

  def handle_call(:reset, _from, _events), do: {:reply, :ok, []}

  defp normalize_key(key) when is_atom(key), do: key
  defp normalize_key(key) when is_binary(key), do: String.to_existing_atom(key)
end
