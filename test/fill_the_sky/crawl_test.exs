defmodule FillTheSky.CrawlTest do
  use FillTheSky.DataCase, async: true

  alias FillTheSky.Crawl

  describe "seed operations" do
    test "add_seed/2 creates a crawl seed" do
      assert {:ok, seed} = Crawl.add_seed("did:plc:seed1", handle: "alice.bsky.social")
      assert seed.did == "did:plc:seed1"
      assert seed.handle == "alice.bsky.social"
      assert seed.status == "pending"
      assert seed.depth == 2
    end

    test "add_seed/2 with custom depth and priority" do
      assert {:ok, seed} = Crawl.add_seed("did:plc:seed2", depth: 3, priority: 10)
      assert seed.depth == 3
      assert seed.priority == 10
    end

    test "add_seed/2 ignores duplicate DIDs" do
      {:ok, _} = Crawl.add_seed("did:plc:dup")
      assert {:ok, _} = Crawl.add_seed("did:plc:dup")
    end

    test "pending_seeds/1 returns pending seeds ordered by priority" do
      {:ok, _} = Crawl.add_seed("did:plc:low", priority: 1)
      {:ok, _} = Crawl.add_seed("did:plc:high", priority: 10)
      {:ok, _} = Crawl.add_seed("did:plc:mid", priority: 5)

      seeds = Crawl.pending_seeds()
      assert length(seeds) == 3
      assert hd(seeds).did == "did:plc:high"
    end

    test "pending_seeds/1 respects limit" do
      for i <- 1..5, do: Crawl.add_seed("did:plc:lim#{i}")
      assert length(Crawl.pending_seeds(3)) == 3
    end

    test "update_seed_status/2 changes status" do
      {:ok, seed} = Crawl.add_seed("did:plc:status")
      assert {:ok, updated} = Crawl.update_seed_status(seed, "crawling")
      assert updated.status == "crawling"
    end

    test "pending_seeds/1 excludes non-pending seeds" do
      {:ok, seed} = Crawl.add_seed("did:plc:done")
      Crawl.update_seed_status(seed, "complete")

      {:ok, _} = Crawl.add_seed("did:plc:still_pending")

      seeds = Crawl.pending_seeds()
      assert length(seeds) == 1
      assert hd(seeds).did == "did:plc:still_pending"
    end
  end

  describe "cursor operations" do
    test "get_or_create_cursor/2 creates new cursor" do
      assert {:ok, cursor} = Crawl.get_or_create_cursor("getFollows", "did:plc:target1")
      assert cursor.endpoint == "getFollows"
      assert cursor.target_did == "did:plc:target1"
      assert cursor.completed == false
      assert cursor.page_count == 0
    end

    test "get_or_create_cursor/2 returns existing cursor" do
      {:ok, original} = Crawl.get_or_create_cursor("getFollows", "did:plc:target2")
      Crawl.update_cursor(original, %{cursor: "abc123", page_count: 3})

      {:ok, found} = Crawl.get_or_create_cursor("getFollows", "did:plc:target2")
      assert found.id == original.id
      assert found.cursor == "abc123"
      assert found.page_count == 3
    end

    test "update_cursor/2 updates cursor state" do
      {:ok, cursor} = Crawl.get_or_create_cursor("getFollowers", "did:plc:upd")

      assert {:ok, updated} =
               Crawl.update_cursor(cursor, %{
                 cursor: "page2cursor",
                 page_count: 1
               })

      assert updated.cursor == "page2cursor"
      assert updated.page_count == 1
    end

    test "update_cursor/2 marks cursor completed" do
      {:ok, cursor} = Crawl.get_or_create_cursor("getFollows", "did:plc:complete")
      assert {:ok, updated} = Crawl.update_cursor(cursor, %{completed: true, page_count: 5})
      assert updated.completed == true
    end

    test "incomplete_cursors/1 returns only incomplete cursors for endpoint" do
      {:ok, c1} = Crawl.get_or_create_cursor("getFollows", "did:plc:inc1")
      {:ok, c2} = Crawl.get_or_create_cursor("getFollows", "did:plc:inc2")
      {:ok, _c3} = Crawl.get_or_create_cursor("getFollowers", "did:plc:inc3")
      Crawl.update_cursor(c1, %{completed: true})

      incomplete = Crawl.incomplete_cursors("getFollows")
      assert length(incomplete) == 1
      assert hd(incomplete).id == c2.id
    end
  end
end
