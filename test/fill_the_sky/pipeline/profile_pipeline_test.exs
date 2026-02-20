defmodule FillTheSky.Pipeline.ProfilePipelineTest do
  use FillTheSky.DataCase, async: false

  alias FillTheSky.Graph

  @moduletag :live_api

  describe "profile enrichment" do
    test "enriches a user stub with profile data from Bluesky API" do
      # Resolve the DID
      {:ok, %{"did" => did}} =
        FillTheSky.Bluesky.Client.resolve_handle("bobbby.online")

      # Create a user stub (no profile data)
      {:ok, user} = Graph.upsert_user_by_did(did)
      assert is_nil(user.profile_fetched_at)
      assert is_nil(user.handle) || user.handle == nil

      # Fetch profile directly (not through pipeline, to test the logic)
      {:ok, %{"profiles" => [profile]}} =
        FillTheSky.Bluesky.Client.get_profiles([did])

      # Apply the profile update
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

      assert {:ok, enriched} = Graph.update_user_profile(user, attrs)
      assert enriched.handle == "bobbby.online"
      assert enriched.profile_fetched_at != nil
      assert is_binary(enriched.display_name) || is_nil(enriched.display_name)
    end

    test "users_needing_profiles returns unenriched users" do
      {:ok, %{"did" => did}} =
        FillTheSky.Bluesky.Client.resolve_handle("bobbby.online")

      {:ok, _} = Graph.upsert_user_by_did(did)

      needing = Graph.users_needing_profiles(10)
      assert length(needing) >= 1
      assert Enum.any?(needing, fn u -> u.did == did end)
    end
  end
end
