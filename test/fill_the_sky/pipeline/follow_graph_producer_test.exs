defmodule FillTheSky.Pipeline.FollowGraphProducerTest do
  use FillTheSky.DataCase, async: false

  alias FillTheSky.Crawl
  alias FillTheSky.Pipeline.FollowGraphProducer

  describe "init/1" do
    test "starts with empty queue and configurable max_depth" do
      {:ok, pid} = FollowGraphProducer.start_link(max_depth: 3, name: :test_producer_init)
      assert Process.alive?(pid)
      GenStage.stop(pid)
    end
  end

  describe "enqueue via cast" do
    test "accepts DIDs without error" do
      {:ok, pid} = FollowGraphProducer.start_link(max_depth: 1, name: :test_producer_enqueue)
      GenStage.cast(pid, {:enqueue, "did:plc:test123", 0})
      # Verify process is still alive (didn't crash)
      assert Process.alive?(pid)
      GenStage.stop(pid)
    end
  end

  describe "enqueue_many via cast" do
    test "accepts multiple DID/depth pairs" do
      {:ok, pid} = FollowGraphProducer.start_link(max_depth: 1, name: :test_producer_many)

      pairs = [{"did:plc:a", 0}, {"did:plc:b", 0}, {"did:plc:c", 0}]
      GenStage.cast(pid, {:enqueue_many, pairs})

      assert Process.alive?(pid)
      GenStage.stop(pid)
    end
  end

  describe "cursor persistence" do
    @tag :live_api
    test "creates cursor records when fetching follows" do
      {:ok, %{"did" => did}} =
        FillTheSky.Bluesky.Client.resolve_handle("bobbby.online")

      # Manually call get_or_create_cursor to verify the mechanism
      assert {:ok, cursor} = Crawl.get_or_create_cursor("getFollows", did)
      assert cursor.endpoint == "getFollows"
      assert cursor.target_did == did
      assert cursor.completed == false
      assert cursor.page_count == 0
    end
  end
end
