defmodule FillTheSky.GraphTest do
  use FillTheSky.DataCase, async: true

  alias FillTheSky.Graph

  describe "user operations" do
    test "upsert_user_by_did/2 creates a new user" do
      assert {:ok, user} = Graph.upsert_user_by_did("did:plc:abc123")
      assert user.did == "did:plc:abc123"
      assert user.crawl_state == "pending"
    end

    test "upsert_user_by_did/2 updates existing user on conflict" do
      {:ok, _} = Graph.upsert_user_by_did("did:plc:abc123", %{handle: "alice.bsky.social"})
      {:ok, user} = Graph.upsert_user_by_did("did:plc:abc123", %{handle: "alice-new.bsky.social"})

      assert user.did == "did:plc:abc123"
      assert user.handle == "alice-new.bsky.social"
    end

    test "get_user/1 returns user by id" do
      {:ok, created} = Graph.upsert_user_by_did("did:plc:abc123")
      assert {:ok, found} = Graph.get_user(created.id)
      assert found.did == "did:plc:abc123"
    end

    test "get_user/1 returns error for missing user" do
      assert {:error, :not_found} = Graph.get_user(Ecto.UUID.generate())
    end

    test "get_user_by_did/1 returns user by DID" do
      {:ok, _} = Graph.upsert_user_by_did("did:plc:findme")
      assert {:ok, user} = Graph.get_user_by_did("did:plc:findme")
      assert user.did == "did:plc:findme"
    end

    test "get_user_by_did/1 returns error for missing DID" do
      assert {:error, :not_found} = Graph.get_user_by_did("did:plc:nope")
    end

    test "update_user_profile/2 updates profile fields" do
      {:ok, user} = Graph.upsert_user_by_did("did:plc:profile")

      assert {:ok, updated} =
               Graph.update_user_profile(user, %{
                 handle: "bob.bsky.social",
                 display_name: "Bob",
                 bio: "Hello world",
                 followers_count: 42,
                 profile_fetched_at: DateTime.utc_now()
               })

      assert updated.handle == "bob.bsky.social"
      assert updated.display_name == "Bob"
      assert updated.bio == "Hello world"
      assert updated.followers_count == 42
      assert updated.profile_fetched_at != nil
    end

    test "batch_upsert_users_by_did/1 inserts multiple users" do
      dids = ["did:plc:one", "did:plc:two", "did:plc:three"]
      {count, _} = Graph.batch_upsert_users_by_did(dids)
      assert count == 3
      assert Graph.user_count() == 3
    end

    test "batch_upsert_users_by_did/1 ignores duplicates" do
      Graph.upsert_user_by_did("did:plc:existing")
      {count, _} = Graph.batch_upsert_users_by_did(["did:plc:existing", "did:plc:new"])
      assert count == 1
      assert Graph.user_count() == 2
    end

    test "search_users/2 finds by handle" do
      {:ok, _} =
        Graph.upsert_user_by_did("did:plc:search1", %{handle: "alice.bsky.social"})

      {:ok, _} =
        Graph.upsert_user_by_did("did:plc:search2", %{handle: "bob.bsky.social"})

      results = Graph.search_users("alice")
      assert length(results) == 1
      assert hd(results).handle == "alice.bsky.social"
    end

    test "search_users/2 finds by bio" do
      {:ok, user} = Graph.upsert_user_by_did("did:plc:bio1", %{handle: "someone.bsky.social"})
      Graph.update_user_profile(user, %{handle: "someone.bsky.social", bio: "Elixir developer"})

      results = Graph.search_users("elixir")
      assert length(results) == 1
    end

    test "search_users/2 respects limit" do
      for i <- 1..5 do
        Graph.upsert_user_by_did("did:plc:lim#{i}", %{handle: "user#{i}.bsky.social"})
      end

      results = Graph.search_users("user", limit: 3)
      assert length(results) == 3
    end

    test "users_needing_profiles/1 returns users without profile_fetched_at" do
      {:ok, _} = Graph.upsert_user_by_did("did:plc:needsprofile")

      {:ok, user2} = Graph.upsert_user_by_did("did:plc:hasprofile")

      Graph.update_user_profile(user2, %{
        handle: "has.bsky.social",
        profile_fetched_at: DateTime.utc_now()
      })

      needing = Graph.users_needing_profiles()
      assert length(needing) == 1
      assert hd(needing).did == "did:plc:needsprofile"
    end
  end

  describe "follow operations" do
    setup do
      {:ok, alice} = Graph.upsert_user_by_did("did:plc:alice")
      {:ok, bob} = Graph.upsert_user_by_did("did:plc:bob")
      {:ok, carol} = Graph.upsert_user_by_did("did:plc:carol")
      %{alice: alice, bob: bob, carol: carol}
    end

    test "create_follow/2 creates a follow relationship", %{alice: alice, bob: bob} do
      assert {:ok, follow} = Graph.create_follow(alice.id, bob.id)
      assert follow.follower_id == alice.id
      assert follow.following_id == bob.id
    end

    test "create_follow/2 ignores duplicate follows", %{alice: alice, bob: bob} do
      {:ok, _} = Graph.create_follow(alice.id, bob.id)
      assert {:ok, _} = Graph.create_follow(alice.id, bob.id)
      assert Graph.follow_count() == 1
    end

    test "batch_upsert_follows/1 inserts multiple follows", ctx do
      follows = [
        %{follower_id: ctx.alice.id, following_id: ctx.bob.id},
        %{follower_id: ctx.alice.id, following_id: ctx.carol.id},
        %{follower_id: ctx.bob.id, following_id: ctx.carol.id}
      ]

      {count, _} = Graph.batch_upsert_follows(follows)
      assert count == 3
      assert Graph.follow_count() == 3
    end

    test "batch_upsert_follows/1 ignores duplicate follows", ctx do
      Graph.create_follow(ctx.alice.id, ctx.bob.id)

      follows = [
        %{follower_id: ctx.alice.id, following_id: ctx.bob.id},
        %{follower_id: ctx.alice.id, following_id: ctx.carol.id}
      ]

      {count, _} = Graph.batch_upsert_follows(follows)
      assert count == 1
      assert Graph.follow_count() == 2
    end

    test "follow_count/0 returns total follow count", ctx do
      assert Graph.follow_count() == 0
      Graph.create_follow(ctx.alice.id, ctx.bob.id)
      assert Graph.follow_count() == 1
    end

    test "user_count/0 returns total user count" do
      assert Graph.user_count() == 3
    end
  end

  describe "export operations" do
    test "export_edges/0 returns follow edges as DID pairs" do
      {:ok, alice} = Graph.upsert_user_by_did("did:plc:exp_alice")
      {:ok, bob} = Graph.upsert_user_by_did("did:plc:exp_bob")
      Graph.create_follow(alice.id, bob.id)

      edges = Graph.export_edges()
      assert ["did:plc:exp_alice", "did:plc:exp_bob"] in edges
    end

    test "export_user_bios/0 returns map of DID to bio" do
      {:ok, user} = Graph.upsert_user_by_did("did:plc:bio_export", %{handle: "bio.bsky.social"})
      Graph.update_user_profile(user, %{handle: "bio.bsky.social", bio: "I love Elixir"})

      bios = Graph.export_user_bios()
      assert bios["did:plc:bio_export"] == "I love Elixir"
    end

    test "export_user_bios/0 excludes users without bios" do
      Graph.upsert_user_by_did("did:plc:nobio")
      bios = Graph.export_user_bios()
      refute Map.has_key?(bios, "did:plc:nobio")
    end
  end
end
