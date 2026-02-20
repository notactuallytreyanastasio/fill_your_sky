defmodule FillTheSky.Pipeline.ProfilePipeline do
  @moduledoc """
  Broadway pipeline that enriches user records with profile data from the Bluesky API.
  Fetches profiles in batches of up to 25 via getProfiles.
  """

  use Broadway

  require Logger

  alias FillTheSky.Bluesky.Client
  alias FillTheSky.Graph
  alias FillTheSky.Pipeline.ProfileProducer

  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    producer_opts = Keyword.get(opts, :producer_opts, [])

    Broadway.start_link(__MODULE__,
      name: opts[:name] || __MODULE__,
      producer: [
        module: {ProfileProducer, producer_opts},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 1]
      ],
      batchers: [
        profiles: [
          concurrency: 1,
          batch_size: 25,
          batch_timeout: 3_000
        ]
      ]
    )
  end

  @impl true
  def handle_message(_processor, message, _ctx) do
    Broadway.Message.put_batcher(message, :profiles)
  end

  @impl true
  def handle_batch(:profiles, messages, _batch_info, _ctx) do
    dids = Enum.map(messages, fn msg -> msg.data.did end)
    user_id_map = Map.new(messages, fn msg -> {msg.data.did, msg.data.user_id} end)

    case Client.get_profiles(dids) do
      {:ok, %{"profiles" => profiles}} ->
        updated =
          Enum.count(profiles, fn profile ->
            user_id = user_id_map[profile["did"]]

            if user_id do
              case Graph.get_user(user_id) do
                {:ok, user} ->
                  attrs = %{
                    handle: profile["handle"],
                    display_name: profile["displayName"],
                    bio: profile["description"],
                    avatar_url: profile["avatar"],
                    followers_count: profile["followersCount"] || 0,
                    following_count: profile["followsCount"] || 0,
                    posts_count: profile["postsCount"] || 0,
                    profile_fetched_at: DateTime.utc_now()
                  }

                  case Graph.update_user_profile(user, attrs) do
                    {:ok, _} -> true
                    {:error, _} -> false
                  end

                {:error, _} ->
                  false
              end
            else
              false
            end
          end)

        Logger.info("Profiles: enriched #{updated}/#{length(dids)} users")

      {:error, reason} ->
        Logger.warning("Profile batch failed: #{inspect(reason)}")
    end

    messages
  end
end
