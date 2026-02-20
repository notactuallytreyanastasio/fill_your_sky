defmodule FillTheSky.Pipeline.ProfileProducer do
  @moduledoc """
  GenStage producer that polls for users needing profile enrichment.
  Emits batches of DIDs for the ProfilePipeline to fetch via getProfiles.
  """

  use GenStage

  alias FillTheSky.Graph

  @poll_interval :timer.seconds(5)
  @batch_size 25

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  @impl true
  def init(opts) do
    poll_interval = Keyword.get(opts, :poll_interval, @poll_interval)
    batch_size = Keyword.get(opts, :batch_size, @batch_size)
    schedule_poll(poll_interval)
    {:producer, %{poll_interval: poll_interval, batch_size: batch_size, buffer: []}}
  end

  @impl true
  def handle_demand(_demand, state) do
    {events, remaining} = Enum.split(state.buffer, 25)

    messages =
      Enum.map(events, fn user ->
        %Broadway.Message{
          data: %{user_id: user.id, did: user.did},
          acknowledger: {Broadway.NoopAcknowledger, nil, nil}
        }
      end)

    {:noreply, messages, %{state | buffer: remaining}}
  end

  @impl true
  def handle_info(:poll, state) do
    schedule_poll(state.poll_interval)
    users = Graph.users_needing_profiles(state.batch_size * 4)

    messages =
      Enum.map(users, fn user ->
        %Broadway.Message{
          data: %{user_id: user.id, did: user.did},
          acknowledger: {Broadway.NoopAcknowledger, nil, nil}
        }
      end)

    {:noreply, messages, state}
  end

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end
end
