defmodule FillTheSky.Bluesky.RateLimiterTest do
  use ExUnit.Case, async: true

  alias FillTheSky.Bluesky.RateLimiter

  setup do
    # Start a rate limiter with small values for fast tests
    {:ok, pid} =
      GenServer.start_link(RateLimiter, [max_tokens: 3, refill_interval: 100], name: nil)

    %{pid: pid}
  end

  test "acquire/0 succeeds when tokens available", %{pid: pid} do
    assert :ok = GenServer.call(pid, :acquire)
  end

  test "tokens decrease with each acquire", %{pid: pid} do
    assert 3 = GenServer.call(pid, :available_tokens)
    GenServer.call(pid, :acquire)
    assert 2 = GenServer.call(pid, :available_tokens)
    GenServer.call(pid, :acquire)
    assert 1 = GenServer.call(pid, :available_tokens)
  end

  test "acquire blocks when no tokens available then unblocks on refill", %{pid: pid} do
    # Exhaust all tokens
    GenServer.call(pid, :acquire)
    GenServer.call(pid, :acquire)
    GenServer.call(pid, :acquire)
    assert 0 = GenServer.call(pid, :available_tokens)

    # This should block briefly until refill (100ms)
    task =
      Task.async(fn ->
        GenServer.call(pid, :acquire, 1000)
      end)

    result = Task.await(task, 1000)
    assert result == :ok
  end

  test "tokens refill after interval", %{pid: pid} do
    GenServer.call(pid, :acquire)
    GenServer.call(pid, :acquire)
    GenServer.call(pid, :acquire)
    assert 0 = GenServer.call(pid, :available_tokens)

    # Wait for refill
    Process.sleep(150)
    assert 3 = GenServer.call(pid, :available_tokens)
  end
end
