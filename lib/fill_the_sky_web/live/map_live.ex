defmodule FillTheSkyWeb.MapLive do
  @moduledoc """
  Main LiveView for the interactive community map.
  Loads the latest community detection run and pushes point data to the deck.gl hook.
  """

  use FillTheSkyWeb, :live_view

  alias FillTheSky.Communities
  alias FillTheSky.Graph

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, :page_title, "Fill The Sky")

    socket =
      assign(socket,
        run: nil,
        communities: [],
        selected_community: nil,
        selected_user: nil,
        search_query: "",
        search_results: [],
        loading: true
      )

    if connected?(socket) do
      send(self(), :load_map)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_map, socket) do
    case Communities.latest_complete_run() do
      {:ok, run} ->
        communities = Communities.get_communities_for_run(run.id)
        map_data = Communities.get_map_data(run.id)

        points =
          Enum.map(map_data, fn p ->
            %{
              user_id: p.user_id,
              did: p.did,
              handle: p.handle,
              display_name: p.display_name,
              x: p.x,
              y: p.y,
              community_index: p.community_index,
              community_label: p.community_label,
              color: p.color
            }
          end)

        community_data =
          Enum.map(communities, fn c ->
            %{
              community_index: c.community_index,
              label: c.label,
              color: c.color,
              member_count: c.member_count,
              centroid_x: c.centroid_x,
              centroid_y: c.centroid_y
            }
          end)

        socket =
          socket
          |> assign(run: run, communities: communities, loading: false)
          |> push_event("map_data", %{points: points, communities: community_data})
          |> push_event("fit_bounds", %{})

        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply, assign(socket, loading: false)}
    end
  end

  @impl true
  def handle_event("select_community", %{"index" => index}, socket) do
    index = if is_binary(index), do: String.to_integer(index), else: index

    new_selected =
      if socket.assigns.selected_community == index, do: nil, else: index

    socket =
      socket
      |> assign(selected_community: new_selected, selected_user: nil)
      |> push_event("select_community", %{index: new_selected})

    {:noreply, socket}
  end

  def handle_event("select_community_from_map", %{"index" => index}, socket) do
    new_selected =
      if socket.assigns.selected_community == index, do: nil, else: index

    {:noreply,
     assign(socket,
       selected_community: new_selected,
       selected_user: nil
     )}
  end

  def handle_event("point_clicked", %{"user_id" => user_id, "community_index" => idx}, socket) do
    case Graph.get_user(user_id) do
      {:ok, user} ->
        {:noreply,
         assign(socket,
           selected_user: user,
           selected_community: idx
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("search", %{"query" => query}, socket) do
    query = String.trim(query)

    results =
      if String.length(query) >= 2 do
        Graph.search_users(query, limit: 10)
      else
        []
      end

    {:noreply, assign(socket, search_query: query, search_results: results)}
  end

  def handle_event("clear_selection", _params, socket) do
    socket =
      socket
      |> assign(selected_community: nil, selected_user: nil)
      |> push_event("select_community", %{index: nil})

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-gray-900">
      <div class="flex-1 relative">
        <div
          id="deck-gl-map"
          phx-hook="DeckGLMap"
          phx-update="ignore"
          class="w-full h-full"
        >
        </div>

        <div :if={@loading} class="absolute inset-0 flex items-center justify-center bg-gray-900/80">
          <div class="text-white text-lg">Loading map data...</div>
        </div>

        <div
          :if={!@loading && is_nil(@run)}
          class="absolute inset-0 flex items-center justify-center bg-gray-900/80"
        >
          <div class="text-center text-white">
            <p class="text-lg mb-2">No community data yet</p>
            <p class="text-sm text-gray-400">
              Run the ML pipeline from
              <a href="/admin/pipeline" class="text-blue-400 underline">Admin &rarr; Pipeline</a>
            </p>
          </div>
        </div>
      </div>

      <div class="w-80 bg-gray-800 text-gray-100 flex flex-col border-l border-gray-700 overflow-hidden">
        <div class="p-4 border-b border-gray-700">
          <h1 class="text-lg font-bold mb-3">Fill The Sky</h1>
          <form phx-change="search" class="relative">
            <input
              type="text"
              name="query"
              value={@search_query}
              placeholder="Search handles or bios..."
              phx-debounce="300"
              class="w-full bg-gray-700 border-gray-600 rounded px-3 py-2 text-sm text-white placeholder-gray-400"
            />
          </form>
          <div :if={@search_results != []} class="mt-2 max-h-48 overflow-y-auto">
            <div
              :for={user <- @search_results}
              class="px-2 py-1.5 hover:bg-gray-700 rounded cursor-pointer text-sm"
            >
              <div class="font-medium">{user.handle || user.did}</div>
              <div :if={user.display_name} class="text-xs text-gray-400">{user.display_name}</div>
            </div>
          </div>
        </div>

        <div :if={@selected_user} class="p-4 border-b border-gray-700 bg-gray-750">
          <div class="flex justify-between items-start">
            <div>
              <div class="font-semibold">{@selected_user.handle || @selected_user.did}</div>
              <div :if={@selected_user.display_name} class="text-sm text-gray-400">
                {@selected_user.display_name}
              </div>
            </div>
            <button phx-click="clear_selection" class="text-gray-500 hover:text-gray-300 text-xs">
              &times;
            </button>
          </div>
          <p :if={@selected_user.bio} class="mt-2 text-sm text-gray-300 line-clamp-3">
            {@selected_user.bio}
          </p>
          <div class="mt-2 flex gap-3 text-xs text-gray-400">
            <span>{@selected_user.followers_count} followers</span>
            <span>{@selected_user.following_count} following</span>
          </div>
          <a
            :if={@selected_user.handle}
            href={"https://bsky.app/profile/#{@selected_user.handle}"}
            target="_blank"
            class="mt-2 inline-block text-xs text-blue-400 hover:text-blue-300"
          >
            View on Bluesky &rarr;
          </a>
        </div>

        <div class="flex-1 overflow-y-auto p-4">
          <div class="flex justify-between items-center mb-3">
            <h2 class="text-sm font-semibold text-gray-400 uppercase tracking-wider">
              Communities
            </h2>
            <button
              :if={@selected_community}
              phx-click="clear_selection"
              class="text-xs text-gray-500 hover:text-gray-300"
            >
              Clear
            </button>
          </div>
          <div class="space-y-1">
            <button
              :for={c <- @communities}
              phx-click="select_community"
              phx-value-index={c.community_index}
              class={[
                "w-full text-left px-3 py-2 rounded text-sm transition-colors",
                c.community_index == @selected_community &&
                  "bg-gray-600 ring-1 ring-gray-500",
                c.community_index != @selected_community &&
                  "hover:bg-gray-700"
              ]}
            >
              <div class="flex items-center gap-2">
                <span
                  class="w-3 h-3 rounded-full inline-block flex-shrink-0"
                  style={"background:#{c.color}"}
                >
                </span>
                <span class="truncate">{c.label || "Community #{c.community_index}"}</span>
                <span class="ml-auto text-xs text-gray-500">{c.member_count}</span>
              </div>
            </button>
          </div>
        </div>

        <div :if={@run} class="p-3 border-t border-gray-700 text-xs text-gray-500">
          Run: {Calendar.strftime(@run.inserted_at, "%Y-%m-%d %H:%M")} &middot; {length(@communities)} communities
        </div>
      </div>
    </div>
    """
  end
end
