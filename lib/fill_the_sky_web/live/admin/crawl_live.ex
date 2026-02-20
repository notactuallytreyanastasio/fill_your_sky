defmodule FillTheSkyWeb.Admin.CrawlLive do
  @moduledoc """
  Admin LiveView for managing the social graph crawl.
  Add seed handles, start/stop crawl, monitor progress.
  """

  use FillTheSkyWeb, :live_view

  require Logger

  alias FillTheSky.Bluesky.Client
  alias FillTheSky.Crawl
  alias FillTheSky.Graph
  alias FillTheSky.Pipeline.{FollowGraphPipeline, FollowGraphProducer, ProfilePipeline}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(2_000, self(), :refresh_stats)

    {:ok,
     assign(socket,
       seed_input: "",
       depth_input: "1",
       seeds: Crawl.list_seeds(),
       user_count: Graph.user_count(),
       follow_count: Graph.follow_count(),
       profiles_enriched: Graph.profiles_enriched_count(),
       seed_stats: Crawl.seed_stats(),
       cursor_stats: Crawl.cursor_stats(),
       crawl_running: pipeline_alive?(FollowGraphPipeline),
       profile_running: pipeline_alive?(ProfilePipeline),
       flash_msg: nil
     )}
  end

  @impl true
  def handle_event("add_seed", %{"handle" => handle, "depth" => depth}, socket) do
    handle = String.trim(handle)
    {depth_int, _} = Integer.parse(depth)

    case Client.resolve_handle(handle) do
      {:ok, %{"did" => did}} ->
        case Crawl.add_seed(did, handle: handle, depth: depth_int) do
          {:ok, _seed} ->
            {:noreply,
             assign(socket,
               seeds: Crawl.list_seeds(),
               seed_input: "",
               flash_msg: "Added #{handle}"
             )}

          {:error, _changeset} ->
            {:noreply, assign(socket, flash_msg: "Seed already exists")}
        end

      {:error, reason} ->
        {:noreply, assign(socket, flash_msg: "Could not resolve handle: #{inspect(reason)}")}
    end
  end

  def handle_event("start_crawl", _params, socket) do
    # Reset any seeds stuck in "crawling" from a crashed previous run
    {reset_count, _} = Crawl.reset_stale_seeds()
    if reset_count > 0, do: Logger.info("Reset #{reset_count} stale seeds to pending")

    max_depth =
      Crawl.pending_seeds(100)
      |> Enum.map(& &1.depth)
      |> Enum.max(fn -> 1 end)

    Logger.info("Starting crawl with max_depth=#{max_depth}")

    result =
      DynamicSupervisor.start_child(
        FillTheSky.PipelineSupervisor,
        {FollowGraphPipeline, producer_opts: [max_depth: max_depth]}
      )

    case result do
      {:ok, _pid} ->
        enqueue_pending_seeds()
        {:noreply, assign(socket, crawl_running: true, seeds: Crawl.list_seeds())}

      {:error, {:already_started, _pid}} ->
        enqueue_pending_seeds()
        {:noreply, assign(socket, crawl_running: true, seeds: Crawl.list_seeds())}

      {:error, reason} ->
        Logger.warning("Failed to start crawl pipeline: #{inspect(reason)}")
        {:noreply, assign(socket, flash_msg: "Failed to start: #{inspect(reason)}")}
    end
  end

  def handle_event("stop_crawl", _params, socket) do
    if pipeline_alive?(FollowGraphPipeline) do
      Broadway.stop(FollowGraphPipeline)
    end

    {:noreply, assign(socket, crawl_running: false)}
  end

  def handle_event("start_profiles", _params, socket) do
    result =
      DynamicSupervisor.start_child(
        FillTheSky.PipelineSupervisor,
        {ProfilePipeline, []}
      )

    case result do
      {:ok, _pid} ->
        {:noreply, assign(socket, profile_running: true)}

      {:error, {:already_started, _pid}} ->
        {:noreply, assign(socket, profile_running: true)}
    end
  end

  def handle_event("stop_profiles", _params, socket) do
    if pipeline_alive?(ProfilePipeline) do
      Broadway.stop(ProfilePipeline)
    end

    {:noreply, assign(socket, profile_running: false)}
  end

  @impl true
  def handle_info(:refresh_stats, socket) do
    {:noreply,
     assign(socket,
       user_count: Graph.user_count(),
       follow_count: Graph.follow_count(),
       profiles_enriched: Graph.profiles_enriched_count(),
       seed_stats: Crawl.seed_stats(),
       cursor_stats: Crawl.cursor_stats(),
       seeds: Crawl.list_seeds(),
       crawl_running: pipeline_alive?(FollowGraphPipeline),
       profile_running: pipeline_alive?(ProfilePipeline)
     )}
  end

  # --- Private ---

  defp enqueue_pending_seeds do
    seeds = Crawl.pending_seeds(100)
    Logger.info("Enqueuing #{length(seeds)} pending seeds")

    Enum.each(seeds, fn seed ->
      Logger.info("Enqueuing seed: #{seed.handle || seed.did} max_depth=#{seed.depth}")
      # Seeds always start at depth 0; seed.depth is the max_depth for the pipeline
      FollowGraphProducer.enqueue(seed.did, 0)
      Crawl.update_seed_status(seed, "crawling")
    end)
  end

  defp pipeline_alive?(module) do
    case Process.whereis(module) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto p-6">
      <h1 class="text-2xl font-bold mb-6">Crawl Admin</h1>

      <%!-- Stats Grid --%>
      <div class="grid grid-cols-4 gap-4 mb-8">
        <.stat_card value={@user_count} label="Users" color="blue" />
        <.stat_card value={@follow_count} label="Follows" color="green" />
        <.stat_card value={@profiles_enriched} label="Profiles Enriched" color="purple" />
        <.stat_card
          value={@cursor_stats.pages_fetched}
          label="API Pages Fetched"
          color="amber"
        />
      </div>

      <%!-- Pipeline Status --%>
      <div class="grid grid-cols-2 gap-4 mb-8">
        <div class={[
          "p-4 rounded-lg border-2",
          @crawl_running && "border-green-400 bg-green-50",
          !@crawl_running && "border-gray-200 bg-gray-50"
        ]}>
          <div class="flex items-center justify-between mb-3">
            <h2 class="font-semibold">Follow Graph Pipeline</h2>
            <span class={[
              "px-2 py-0.5 rounded-full text-xs font-medium",
              @crawl_running && "bg-green-200 text-green-800",
              !@crawl_running && "bg-gray-200 text-gray-600"
            ]}>
              {if @crawl_running, do: "Running", else: "Stopped"}
            </span>
          </div>
          <div class="grid grid-cols-3 gap-2 text-sm mb-3">
            <div>
              <span class="text-gray-500">Cursors:</span>
              <span class="font-medium">{@cursor_stats.completed}/{@cursor_stats.total}</span>
            </div>
            <div>
              <span class="text-gray-500">Seeds crawling:</span>
              <span class="font-medium">{@seed_stats.crawling}</span>
            </div>
            <div>
              <span class="text-gray-500">Seeds done:</span>
              <span class="font-medium">{@seed_stats.complete}</span>
            </div>
          </div>
          <div :if={@cursor_stats.total > 0} class="mb-3">
            <div class="w-full bg-gray-200 rounded-full h-2">
              <div
                class="bg-green-500 h-2 rounded-full transition-all duration-500"
                style={"width: #{progress_pct(@cursor_stats.completed, @cursor_stats.total)}%"}
              >
              </div>
            </div>
            <div class="text-xs text-gray-500 mt-1">
              {progress_pct(@cursor_stats.completed, @cursor_stats.total)}% of cursors complete
            </div>
          </div>
          <button
            :if={!@crawl_running}
            phx-click="start_crawl"
            class="w-full bg-green-600 text-white px-4 py-2 rounded hover:bg-green-700 text-sm"
          >
            Start Crawl
          </button>
          <button
            :if={@crawl_running}
            phx-click="stop_crawl"
            class="w-full bg-red-600 text-white px-4 py-2 rounded hover:bg-red-700 text-sm"
          >
            Stop Crawl
          </button>
        </div>

        <div class={[
          "p-4 rounded-lg border-2",
          @profile_running && "border-purple-400 bg-purple-50",
          !@profile_running && "border-gray-200 bg-gray-50"
        ]}>
          <div class="flex items-center justify-between mb-3">
            <h2 class="font-semibold">Profile Enrichment</h2>
            <span class={[
              "px-2 py-0.5 rounded-full text-xs font-medium",
              @profile_running && "bg-purple-200 text-purple-800",
              !@profile_running && "bg-gray-200 text-gray-600"
            ]}>
              {if @profile_running, do: "Running", else: "Stopped"}
            </span>
          </div>
          <div class="text-sm mb-3">
            <span class="text-gray-500">Enriched:</span>
            <span class="font-medium">{@profiles_enriched}/{@user_count}</span>
            <span class="text-gray-400">
              ({@user_count - @profiles_enriched} remaining)
            </span>
          </div>
          <div :if={@user_count > 0} class="mb-3">
            <div class="w-full bg-gray-200 rounded-full h-2">
              <div
                class="bg-purple-500 h-2 rounded-full transition-all duration-500"
                style={"width: #{progress_pct(@profiles_enriched, @user_count)}%"}
              >
              </div>
            </div>
            <div class="text-xs text-gray-500 mt-1">
              {progress_pct(@profiles_enriched, @user_count)}% enriched
            </div>
          </div>
          <button
            :if={!@profile_running}
            phx-click="start_profiles"
            class="w-full bg-purple-600 text-white px-4 py-2 rounded hover:bg-purple-700 text-sm"
          >
            Start Profile Enrichment
          </button>
          <button
            :if={@profile_running}
            phx-click="stop_profiles"
            class="w-full bg-red-600 text-white px-4 py-2 rounded hover:bg-red-700 text-sm"
          >
            Stop Profiles
          </button>
        </div>
      </div>

      <%!-- Add Seed --%>
      <div class="mb-8">
        <h2 class="text-lg font-semibold mb-3">Add Seed</h2>
        <form phx-submit="add_seed" class="flex gap-2">
          <input
            type="text"
            name="handle"
            value={@seed_input}
            placeholder="alice.bsky.social"
            class="flex-1 border rounded px-3 py-2"
          />
          <input
            type="number"
            name="depth"
            value={@depth_input}
            min="0"
            max="3"
            class="w-20 border rounded px-3 py-2"
          />
          <button type="submit" class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700">
            Add
          </button>
        </form>
        <p :if={@flash_msg} class="mt-2 text-sm text-gray-600">{@flash_msg}</p>
      </div>

      <%!-- Seeds Table --%>
      <div>
        <h2 class="text-lg font-semibold mb-3">Seeds</h2>
        <table class="w-full text-sm">
          <thead>
            <tr class="border-b">
              <th class="text-left py-2">Handle</th>
              <th class="text-left py-2">DID</th>
              <th class="text-left py-2">Depth</th>
              <th class="text-left py-2">Status</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={seed <- @seeds} class="border-b">
              <td class="py-2">{seed.handle || "—"}</td>
              <td class="py-2 font-mono text-xs">{String.slice(seed.did, 0, 24)}...</td>
              <td class="py-2">{seed.depth}</td>
              <td class="py-2">
                <span class={[
                  "px-2 py-0.5 rounded text-xs",
                  seed.status == "complete" && "bg-green-100 text-green-700",
                  seed.status == "crawling" && "bg-yellow-100 text-yellow-700",
                  seed.status == "pending" && "bg-gray-100 text-gray-700",
                  seed.status == "error" && "bg-red-100 text-red-700"
                ]}>
                  {seed.status}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
        <p :if={@seeds == []} class="text-gray-500 py-4 text-sm">No seeds added yet.</p>
      </div>
    </div>
    """
  end

  defp progress_pct(_done, 0), do: 0
  defp progress_pct(done, total), do: round(done / total * 100)

  attr :value, :any, required: true
  attr :label, :string, required: true
  attr :color, :string, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class={"bg-#{@color}-50 p-4 rounded-lg"}>
      <div class={"text-3xl font-bold text-#{@color}-600"}>{@value}</div>
      <div class={"text-sm text-#{@color}-500"}>{@label}</div>
    </div>
    """
  end
end
