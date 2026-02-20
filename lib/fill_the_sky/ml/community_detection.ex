defmodule FillTheSky.ML.CommunityDetection do
  @moduledoc """
  Orchestrates the full ML pipeline: exports graph data from Postgres,
  runs Leiden + Node2Vec + UMAP via PythonWorker, and imports results.
  """

  require Logger

  alias FillTheSky.Communities
  alias FillTheSky.Graph
  alias FillTheSky.ML.PythonWorker

  @spec run(keyword()) :: {:ok, Communities.CommunityRun.t()} | {:error, term()}
  def run(opts \\ []) do
    resolution = Keyword.get(opts, :resolution, 1.0)
    n2v_dimensions = Keyword.get(opts, :n2v_dimensions, 64)

    with {:ok, run} <-
           Communities.create_run(%{
             status: "running",
             leiden_resolution: resolution,
             node2vec_dimensions: n2v_dimensions
           }),
         {:ok, run} <- execute_pipeline(run, resolution, n2v_dimensions) do
      {:ok, run}
    else
      {:error, reason} = err ->
        Logger.error("Community detection failed: #{inspect(reason)}")
        err
    end
  end

  # --- Private ---

  defp execute_pipeline(run, resolution, n2v_dimensions) do
    Logger.info("ML step 1/5: Exporting graph data from Postgres...")
    Communities.update_run(run, %{status: "exporting"})

    edges = Graph.export_edges()
    bios = Graph.export_user_bios()
    user_count = Graph.user_count()
    edge_count = length(edges)

    Logger.info("ML step 2/5: Exported #{user_count} users, #{edge_count} edges. Starting Python pipeline...")
    Communities.update_run(run, %{status: "computing", user_count: user_count, edge_count: edge_count})

    case PythonWorker.run_pipeline(%{
           edges: edges,
           bios: bios,
           resolution: resolution,
           n2v_dimensions: n2v_dimensions
         }) do
      {:ok, results} ->
        Logger.info("ML step 4/5: Python complete. Importing results...")
        Communities.update_run(run, %{status: "importing"})
        import_results(run, results)

      {:error, reason} ->
        Communities.update_run(run, %{status: "error", error_message: inspect(reason)})
        {:error, reason}
    end
  end

  defp import_results(run, results) do
    # Build user DID -> ID map for embedding insertion
    user_id_map = build_user_id_map()

    # Insert communities
    communities =
      Enum.map(results["communities"], fn c ->
        %{
          community_index: c["index"],
          label: c["label"],
          top_terms: c["top_terms"] || [],
          color: c["color"],
          member_count: c["member_count"] || 0,
          centroid_x: c["centroid_x"],
          centroid_y: c["centroid_y"]
        }
      end)

    {community_count, _} = Communities.batch_insert_communities(run.id, communities)

    # Build community_index -> community_id map
    community_id_map =
      Communities.get_communities_for_run(run.id)
      |> Map.new(fn c -> {c.community_index, c.id} end)

    # Insert user embeddings
    embeddings =
      results["embeddings"]
      |> Enum.filter(fn e -> Map.has_key?(user_id_map, e["did"]) end)
      |> Enum.map(fn e ->
        %{
          user_id: user_id_map[e["did"]],
          run_id: run.id,
          community_id: community_id_map[e["community"]],
          x: e["x"],
          y: e["y"]
        }
      end)

    {embedding_count, _} = Communities.batch_insert_embeddings(embeddings)

    Logger.info(
      "ML pipeline complete: #{community_count} communities, #{embedding_count} embeddings"
    )

    Communities.update_run(run, %{
      status: "complete",
      community_count: community_count
    })
  end

  defp build_user_id_map do
    import Ecto.Query

    FillTheSky.Repo.all(
      from(u in Graph.User,
        select: {u.did, u.id}
      )
    )
    |> Map.new()
  end
end
