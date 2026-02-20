defmodule FillTheSky.Bluesky.ClientTest do
  use ExUnit.Case, async: true

  alias FillTheSky.Bluesky.Client

  # These tests hit the live Bluesky API.
  # Tag them so they can be excluded in CI: mix test --exclude live_api
  @moduletag :live_api

  describe "resolve_handle/1" do
    test "resolves a valid handle to a DID" do
      assert {:ok, %{"did" => did}} = Client.resolve_handle("bobbby.online")
      assert String.starts_with?(did, "did:plc:")
    end

    test "returns error for invalid handle" do
      assert {:error, {:api_error, 400, _}} =
               Client.resolve_handle("this-handle-does-not-exist-zzz.bsky.social")
    end
  end

  describe "get_follows/2" do
    test "fetches follows for a known user" do
      {:ok, %{"did" => did}} = Client.resolve_handle("bobbby.online")
      assert {:ok, %{"follows" => follows}} = Client.get_follows(did)
      assert is_list(follows)
    end

    test "returns paginated results with cursor" do
      {:ok, %{"did" => did}} = Client.resolve_handle("bobbby.online")
      {:ok, result} = Client.get_follows(did)

      if Map.has_key?(result, "cursor") && result["cursor"] do
        {:ok, page2} = Client.get_follows(did, result["cursor"])
        assert is_list(page2["follows"])
      end
    end
  end

  describe "get_followers/2" do
    test "fetches followers for a known user" do
      {:ok, %{"did" => did}} = Client.resolve_handle("bobbby.online")
      assert {:ok, %{"followers" => followers}} = Client.get_followers(did)
      assert is_list(followers)
    end
  end

  describe "get_profile/1" do
    test "fetches a user profile" do
      {:ok, %{"did" => did}} = Client.resolve_handle("bobbby.online")
      assert {:ok, profile} = Client.get_profile(did)
      assert profile["handle"] == "bobbby.online"
      assert Map.has_key?(profile, "displayName")
    end
  end

  describe "get_profiles/1" do
    test "fetches multiple profiles in batch" do
      {:ok, %{"did" => did}} = Client.resolve_handle("bobbby.online")
      assert {:ok, %{"profiles" => profiles}} = Client.get_profiles([did])
      assert length(profiles) == 1
      assert hd(profiles)["handle"] == "bobbby.online"
    end
  end

  describe "get_author_feed/2" do
    test "fetches posts for a user" do
      {:ok, %{"did" => did}} = Client.resolve_handle("bobbby.online")
      assert {:ok, %{"feed" => feed}} = Client.get_author_feed(did)
      assert is_list(feed)
    end
  end
end
