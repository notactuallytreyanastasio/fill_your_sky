defmodule FillTheSky.Bluesky.RateLimiter do
  @moduledoc """
  Token bucket rate limiter for Bluesky API requests.
  Limits to a configurable number of requests per interval.
  """

  use GenServer

  @type state :: %{
          tokens: non_neg_integer(),
          max_tokens: non_neg_integer(),
          refill_interval: non_neg_integer(),
          waiters: :queue.queue()
        }

  @default_max_tokens 90
  @default_refill_interval :timer.seconds(5)

  # --- Public API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec acquire(timeout()) :: :ok | {:error, :timeout}
  def acquire(timeout \\ 10_000) do
    GenServer.call(__MODULE__, :acquire, timeout)
  end

  @spec available_tokens() :: non_neg_integer()
  def available_tokens do
    GenServer.call(__MODULE__, :available_tokens)
  end

  # --- GenServer callbacks ---

  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(opts) do
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)
    refill_interval = Keyword.get(opts, :refill_interval, @default_refill_interval)

    schedule_refill(refill_interval)

    {:ok,
     %{
       tokens: max_tokens,
       max_tokens: max_tokens,
       refill_interval: refill_interval,
       waiters: :queue.new()
     }}
  end

  @impl true
  def handle_call(:acquire, from, %{tokens: 0} = state) do
    {:noreply, %{state | waiters: :queue.in(from, state.waiters)}}
  end

  def handle_call(:acquire, _from, %{tokens: tokens} = state) when tokens > 0 do
    {:reply, :ok, %{state | tokens: tokens - 1}}
  end

  def handle_call(:available_tokens, _from, state) do
    {:reply, state.tokens, state}
  end

  @impl true
  def handle_info(:refill, state) do
    schedule_refill(state.refill_interval)
    state = refill_tokens(state)
    state = drain_waiters(state)
    {:noreply, state}
  end

  # --- Private ---

  defp schedule_refill(interval) do
    Process.send_after(self(), :refill, interval)
  end

  defp refill_tokens(state) do
    %{state | tokens: state.max_tokens}
  end

  defp drain_waiters(%{tokens: 0} = state), do: state

  defp drain_waiters(state) do
    case :queue.out(state.waiters) do
      {:empty, _} ->
        state

      {{:value, waiter}, rest} ->
        GenServer.reply(waiter, :ok)
        drain_waiters(%{state | tokens: state.tokens - 1, waiters: rest})
    end
  end
end
