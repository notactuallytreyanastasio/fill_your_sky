defmodule FillTheSky.Pipeline.FollowGraphProducer do
  @moduledoc """
  GenStage producer that crawls the Bluesky follow graph via cursor-based pagination.
  Receives seed DIDs, paginates through getFollows for each, and emits follow edges
  as Broadway messages.
  """

  use GenStage

  require Logger

  alias FillTheSky.Bluesky.Client
  alias FillTheSky.Crawl

  @type state :: %{
          queue: :queue.queue(),
          max_depth: non_neg_integer()
        }

  # --- Public API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  @default_broadway FillTheSky.Pipeline.FollowGraphPipeline

  @spec enqueue(String.t(), non_neg_integer()) :: :ok
  def enqueue(did, depth \\ 0) do
    [producer] = Broadway.producer_names(@default_broadway)
    GenStage.cast(producer, {:enqueue, did, depth})
  end

  @spec enqueue(atom(), String.t(), non_neg_integer()) :: :ok
  def enqueue(broadway, did, depth) when is_atom(broadway) do
    [producer] = Broadway.producer_names(broadway)
    GenStage.cast(producer, {:enqueue, did, depth})
  end

  @spec enqueue_many(list({String.t(), non_neg_integer()})) :: :ok
  def enqueue_many(did_depth_pairs) do
    [producer] = Broadway.producer_names(@default_broadway)
    GenStage.cast(producer, {:enqueue_many, did_depth_pairs})
  end

  @spec enqueue_many(atom(), list({String.t(), non_neg_integer()})) :: :ok
  def enqueue_many(broadway, did_depth_pairs) when is_atom(broadway) do
    [producer] = Broadway.producer_names(broadway)
    GenStage.cast(producer, {:enqueue_many, did_depth_pairs})
  end

  # --- GenStage callbacks ---

  @impl true
  @spec init(keyword()) :: {:producer, state()}
  def init(opts) do
    max_depth = Keyword.get(opts, :max_depth, 2)
    Logger.info("FollowGraphProducer started with max_depth=#{max_depth}")

    {:producer,
     %{
       queue: :queue.new(),
       max_depth: max_depth
     }}
  end

  @impl true
  def handle_cast({:enqueue, did, depth}, state) do
    new_queue = :queue.in({did, depth}, state.queue)
    state = %{state | queue: new_queue}
    {events, state} = dispatch_events(state)
    {:noreply, events, state}
  end

  def handle_cast({:enqueue_many, pairs}, state) do
    new_queue =
      Enum.reduce(pairs, state.queue, fn {did, depth}, q ->
        :queue.in({did, depth}, q)
      end)

    state = %{state | queue: new_queue}
    {events, state} = dispatch_events(state)
    {:noreply, events, state}
  end

  @impl true
  def handle_demand(_demand, state) do
    {events, state} = dispatch_events(state)
    {:noreply, events, state}
  end

  # --- Private ---

  defp dispatch_events(%{queue: {[], []}} = state), do: {[], state}

  defp dispatch_events(state) do
    case :queue.out(state.queue) do
      {:empty, _} ->
        {[], state}

      {{:value, {did, depth}}, rest_queue} ->
        state = %{state | queue: rest_queue}

        case fetch_follow_page(did) do
          {:ok, follows, new_dids, cursor_completed} ->
            events =
              build_events(follows, did, depth, state.max_depth, new_dids, cursor_completed)

            Logger.info(
              "Producer: #{length(events)} events for #{did} (depth=#{depth}, completed=#{cursor_completed})"
            )

            {events, state}

          {:error, reason} ->
            Logger.warning("Failed to fetch follows for #{did}: #{inspect(reason)}")
            dispatch_events(state)
        end
    end
  end

  defp fetch_follow_page(did) do
    with {:ok, cursor_record} <- Crawl.get_or_create_cursor("getFollows", did) do
      if cursor_record.completed do
        {:ok, [], [], true}
      else
        case Client.get_follows(did, cursor_record.cursor) do
          {:ok, %{"follows" => follows} = result} ->
            new_cursor = result["cursor"]
            completed = is_nil(new_cursor) or new_cursor == ""

            Crawl.update_cursor(cursor_record, %{
              cursor: new_cursor,
              completed: completed,
              page_count: cursor_record.page_count + 1
            })

            new_dids = Enum.map(follows, & &1["did"])

            follow_edges =
              Enum.map(follows, fn f ->
                %{
                  follower_did: did,
                  following_did: f["did"],
                  following_handle: f["handle"],
                  following_display_name: f["displayName"]
                }
              end)

            {:ok, follow_edges, new_dids, completed}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  defp build_events(follows, did, depth, max_depth, new_dids, cursor_completed) do
    follow_events =
      Enum.map(follows, fn edge ->
        %Broadway.Message{
          data: %{type: :follow_edge, edge: edge},
          acknowledger: {Broadway.NoopAcknowledger, nil, nil}
        }
      end)

    # Re-enqueue the source DID to fetch the next page if not done
    if not cursor_completed do
      GenStage.cast(self(), {:enqueue, did, depth})
    end

    # Emit discovery events on EVERY page (not just last) so BFS expands properly
    discovery_events =
      if depth < max_depth and new_dids != [] do
        [
          %Broadway.Message{
            data: %{type: :discovered_dids, dids: new_dids, depth: depth + 1},
            acknowledger: {Broadway.NoopAcknowledger, nil, nil}
          }
        ]
      else
        []
      end

    follow_events ++ discovery_events
  end
end
