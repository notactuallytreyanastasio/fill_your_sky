defmodule FillTheSky.CommunitiesTest do
  use FillTheSky.DataCase, async: true

  alias FillTheSky.Communities
  alias FillTheSky.Graph

  describe "community runs" do
    test "create_run/1 creates a pending run by default" do
      assert {:ok, run} = Communities.create_run(%{})
      assert run.status == "pending"
      assert run.leiden_resolution == 1.0
      assert run.node2vec_dimensions == 64
    end

    test "create_run/1 accepts custom parameters" do
      assert {:ok, run} =
               Communities.create_run(%{
                 status: "running",
                 leiden_resolution: 0.5,
                 node2vec_dimensions: 128
               })

      assert run.status == "running"
      assert run.leiden_resolution == 0.5
      assert run.node2vec_dimensions == 128
    end

    test "get_run/1 returns the run" do
      {:ok, run} = Communities.create_run(%{})
      assert {:ok, fetched} = Communities.get_run(run.id)
      assert fetched.id == run.id
    end

    test "get_run/1 returns error for missing run" do
      assert {:error, :not_found} = Communities.get_run(Ecto.UUID.generate())
    end

    test "update_run/2 updates status and counts" do
      {:ok, run} = Communities.create_run(%{})

      assert {:ok, updated} =
               Communities.update_run(run, %{
                 status: "complete",
                 user_count: 100,
                 edge_count: 500,
                 community_count: 5
               })

      assert updated.status == "complete"
      assert updated.user_count == 100
      assert updated.community_count == 5
    end

    test "latest_complete_run/0 returns most recent complete run" do
      {:ok, _pending} = Communities.create_run(%{status: "pending"})
      {:ok, complete} = Communities.create_run(%{status: "complete"})
      {:ok, _error} = Communities.create_run(%{status: "error"})

      assert {:ok, latest} = Communities.latest_complete_run()
      assert latest.id == complete.id
    end

    test "latest_complete_run/0 returns error when none exist" do
      assert {:error, :not_found} = Communities.latest_complete_run()
    end

    test "list_runs/0 returns all runs ordered by date" do
      {:ok, _r1} = Communities.create_run(%{status: "complete"})
      {:ok, _r2} = Communities.create_run(%{status: "running"})

      runs = Communities.list_runs()
      assert length(runs) == 2
    end
  end

  describe "communities" do
    test "batch_insert_communities/2 inserts communities for a run" do
      {:ok, run} = Communities.create_run(%{})

      communities = [
        %{
          community_index: 0,
          label: "Tech",
          top_terms: ["elixir", "rust"],
          color: "hsl(0,70%,50%)",
          member_count: 42
        },
        %{
          community_index: 1,
          label: "Art",
          top_terms: ["painting", "sculpture"],
          color: "hsl(120,70%,50%)",
          member_count: 28
        }
      ]

      {count, _} = Communities.batch_insert_communities(run.id, communities)
      assert count == 2
    end

    test "get_communities_for_run/1 returns communities ordered by index" do
      {:ok, run} = Communities.create_run(%{})

      Communities.batch_insert_communities(run.id, [
        %{community_index: 2, label: "C"},
        %{community_index: 0, label: "A"},
        %{community_index: 1, label: "B"}
      ])

      communities = Communities.get_communities_for_run(run.id)
      assert length(communities) == 3
      assert Enum.map(communities, & &1.community_index) == [0, 1, 2]
    end
  end

  describe "user embeddings" do
    test "batch_insert_embeddings/1 inserts embedding records" do
      {:ok, run} = Communities.create_run(%{})
      {:ok, user} = Graph.upsert_user_by_did("did:plc:test1")

      Communities.batch_insert_communities(run.id, [
        %{community_index: 0, label: "Test"}
      ])

      [community] = Communities.get_communities_for_run(run.id)

      embeddings = [
        %{user_id: user.id, run_id: run.id, community_id: community.id, x: 1.5, y: -2.3}
      ]

      {count, _} = Communities.batch_insert_embeddings(embeddings)
      assert count == 1
    end

    test "get_map_data/1 returns joined data for visualization" do
      {:ok, run} = Communities.create_run(%{})
      {:ok, user} = Graph.upsert_user_by_did("did:plc:maptest")
      Graph.update_user_profile(user, %{handle: "maptest.bsky.social", display_name: "Map Test"})

      Communities.batch_insert_communities(run.id, [
        %{community_index: 0, label: "TestCluster", color: "hsl(0,70%,50%)"}
      ])

      [community] = Communities.get_communities_for_run(run.id)

      Communities.batch_insert_embeddings([
        %{user_id: user.id, run_id: run.id, community_id: community.id, x: 3.14, y: 2.72}
      ])

      data = Communities.get_map_data(run.id)
      assert length(data) == 1
      [point] = data
      assert point.did == "did:plc:maptest"
      assert point.handle == "maptest.bsky.social"
      assert point.x == 3.14
      assert point.community_label == "TestCluster"
    end
  end
end
