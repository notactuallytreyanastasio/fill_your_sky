defmodule FillTheSky.Pipeline.FollowGraphPipeline do
  @moduledoc """
  Broadway pipeline that processes follow graph data from the Bluesky API.
  Handles follow edge messages and discovered DID messages, upserting into the database.
  """

  use Broadway

  require Logger

  alias FillTheSky.Graph
  alias FillTheSky.Pipeline.FollowGraphProducer

  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    producer_opts = Keyword.get(opts, :producer_opts, [])

    Broadway.start_link(__MODULE__,
      name: opts[:name] || __MODULE__,
      producer: [
        module: {FollowGraphProducer, producer_opts},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 2]
      ],
      batchers: [
        follows: [
          concurrency: 2,
          batch_size: 100,
          batch_timeout: 2_000
        ],
        discovery: [
          concurrency: 1,
          batch_size: 10,
          batch_timeout: 1_000
        ]
      ]
    )
  end

  @impl true
  def handle_message(_processor, %Broadway.Message{data: %{type: :follow_edge}} = message, _ctx) do
    Broadway.Message.put_batcher(message, :follows)
  end

  def handle_message(_processor, %Broadway.Message{data: %{type: :discovered_dids}} = message, _ctx) do
    Broadway.Message.put_batcher(message, :discovery)
  end

  def handle_message(_processor, message, _ctx) do
    Broadway.Message.failed(message, "unknown message type")
  end

  @impl true
  def handle_batch(:follows, messages, _batch_info, _ctx) do
    edges =
      messages
      |> Enum.map(fn msg -> msg.data.edge end)
      |> Enum.uniq_by(fn e -> {e.follower_did, e.following_did} end)

    # Upsert all discovered users (DID stubs)
    all_dids =
      edges
      |> Enum.flat_map(fn e -> [e.follower_did, e.following_did] end)
      |> Enum.uniq()

    {user_count, _} = Graph.batch_upsert_users_by_did(all_dids)

    # Now we need the user IDs to insert follows
    user_id_map = build_user_id_map(all_dids)

    follow_entries =
      edges
      |> Enum.filter(fn e ->
        Map.has_key?(user_id_map, e.follower_did) and
          Map.has_key?(user_id_map, e.following_did)
      end)
      |> Enum.map(fn e ->
        %{
          follower_id: user_id_map[e.follower_did],
          following_id: user_id_map[e.following_did]
        }
      end)

    {follow_count, _} = Graph.batch_upsert_follows(follow_entries)

    Logger.info(
      "Batch: #{user_count} users upserted, #{follow_count} follows upserted (#{length(edges)} edges)"
    )

    messages
  end

  def handle_batch(:discovery, messages, _batch_info, _ctx) do
    for msg <- messages do
      %{dids: dids, depth: depth} = msg.data
      pairs = Enum.map(dids, fn did -> {did, depth} end)
      FollowGraphProducer.enqueue_many(pairs)
    end

    messages
  end

  # --- Private ---

  defp build_user_id_map(dids) do
    import Ecto.Query

    FillTheSky.Repo.all(
      from(u in Graph.User,
        where: u.did in ^dids,
        select: {u.did, u.id}
      )
    )
    |> Map.new()
  end
end
