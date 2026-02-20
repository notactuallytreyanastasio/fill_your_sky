defmodule FillTheSky.Pipeline.FollowGraphPipelineTest do
  use FillTheSky.DataCase, async: false

  alias FillTheSky.Graph
  alias FillTheSky.Pipeline.FollowGraphPipeline

  @moduletag :live_api

  setup do
    # Broadway spawns its own processes that need DB access.
    # Switch to shared sandbox mode so all processes see the same connection.
    Ecto.Adapters.SQL.Sandbox.mode(FillTheSky.Repo, :auto)
    :ok
  end

  defp poll_until(_fun, remaining) when remaining <= 0,
    do: flunk("Condition not met within timeout")

  defp poll_until(fun, remaining) when remaining > 0 do
    if fun.() do
      :ok
    else
      receive do
      after
        100 -> poll_until(fun, remaining - 100)
      end
    end
  end

  describe "real-world crawl from @bobbby.online" do
    test "crawls depth-0 follows and populates database" do
      # Resolve the seed DID
      assert {:ok, %{"did" => did}} =
               FillTheSky.Bluesky.Client.resolve_handle("bobbby.online")

      # Start the pipeline with depth 0 (only direct follows, no BFS)
      {:ok, pipeline} =
        FollowGraphPipeline.start_link(
          name: :test_crawl_pipeline,
          producer_opts: [max_depth: 0, name: :test_crawl_producer]
        )

      # Enqueue the seed
      FillTheSky.Pipeline.FollowGraphProducer.enqueue(:test_crawl_producer, did, 0)

      # Poll until data lands in the database
      poll_until(fn -> Graph.user_count() > 0 and Graph.follow_count() > 0 end, 10_000)

      user_count = Graph.user_count()
      follow_count = Graph.follow_count()

      assert user_count > 0, "Expected users to be created, got #{user_count}"
      assert follow_count > 0, "Expected follows to be created, got #{follow_count}"

      # Verify the seed user exists
      assert {:ok, seed_user} = Graph.get_user_by_did(did)
      assert seed_user.did == did

      # Stop the pipeline
      Broadway.stop(pipeline)
    end
  end
end
