defmodule FillTheSkyWeb.Admin.PipelineLive do
  @moduledoc """
  Admin LiveView for triggering and monitoring ML pipeline runs.
  """

  use FillTheSkyWeb, :live_view

  alias FillTheSky.Communities
  alias FillTheSky.Graph
  alias FillTheSky.ML.CommunityDetection

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(3_000, self(), :refresh_runs)

    {:ok,
     assign(socket,
       runs: Communities.list_runs(),
       user_count: Graph.user_count(),
       follow_count: Graph.follow_count(),
       resolution: "1.0",
       dimensions: "64",
       running: false
     )}
  end

  @impl true
  def handle_event("run_pipeline", %{"resolution" => res, "dimensions" => dims}, socket) do
    {resolution, _} = Float.parse(res)
    {dimensions, _} = Integer.parse(dims)

    # Run async so we don't block the LiveView
    task_ref =
      Task.async(fn ->
        CommunityDetection.run(resolution: resolution, n2v_dimensions: dimensions)
      end)

    {:noreply, assign(socket, running: true, task_ref: task_ref.ref)}
  end

  @impl true
  def handle_info(:refresh_runs, socket) do
    {:noreply, assign(socket, runs: Communities.list_runs())}
  end

  def handle_info({ref, result}, socket) when is_reference(ref) do
    if ref == socket.assigns[:task_ref] do
      Process.demonitor(ref, [:flush])

      flash =
        case result do
          {:ok, run} -> "Pipeline complete: #{run.community_count} communities detected"
          {:error, reason} -> "Pipeline failed: #{inspect(reason)}"
        end

      {:noreply,
       assign(socket,
         running: false,
         task_ref: nil,
         runs: Communities.list_runs()
       )
       |> put_flash(:info, flash)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, socket) when is_reference(ref) do
    if ref == socket.assigns[:task_ref] do
      {:noreply,
       assign(socket, running: false, task_ref: nil)
       |> put_flash(:error, "Pipeline crashed: #{inspect(reason)}")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto p-6">
      <h1 class="text-2xl font-bold mb-6">ML Pipeline</h1>

      <div class="grid grid-cols-2 gap-4 mb-8">
        <div class="bg-blue-50 p-4 rounded-lg">
          <div class="text-3xl font-bold text-blue-600">{@user_count}</div>
          <div class="text-sm text-blue-500">Users in Graph</div>
        </div>
        <div class="bg-green-50 p-4 rounded-lg">
          <div class="text-3xl font-bold text-green-600">{@follow_count}</div>
          <div class="text-sm text-green-500">Follow Edges</div>
        </div>
      </div>

      <div class="mb-8 bg-gray-50 p-4 rounded-lg">
        <h2 class="text-lg font-semibold mb-3">Run Community Detection</h2>
        <form phx-submit="run_pipeline" class="flex gap-3 items-end">
          <div>
            <label class="block text-sm text-gray-600 mb-1">Leiden Resolution</label>
            <input
              type="text"
              name="resolution"
              value={@resolution}
              class="w-32 border rounded px-3 py-2"
            />
          </div>
          <div>
            <label class="block text-sm text-gray-600 mb-1">Node2Vec Dims</label>
            <input
              type="number"
              name="dimensions"
              value={@dimensions}
              min="16"
              max="256"
              class="w-32 border rounded px-3 py-2"
            />
          </div>
          <button
            type="submit"
            disabled={@running}
            class={[
              "px-4 py-2 rounded text-white",
              !@running && "bg-indigo-600 hover:bg-indigo-700",
              @running && "bg-gray-400 cursor-not-allowed"
            ]}
          >
            {if @running, do: "Running...", else: "Run Pipeline"}
          </button>
        </form>
      </div>

      <div>
        <h2 class="text-lg font-semibold mb-3">Pipeline Runs</h2>
        <table class="w-full text-sm">
          <thead>
            <tr class="border-b">
              <th class="text-left py-2">Date</th>
              <th class="text-left py-2">Status</th>
              <th class="text-right py-2">Users</th>
              <th class="text-right py-2">Edges</th>
              <th class="text-right py-2">Communities</th>
              <th class="text-right py-2">Resolution</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={run <- @runs} class="border-b">
              <td class="py-2">{Calendar.strftime(run.inserted_at, "%Y-%m-%d %H:%M")}</td>
              <td class="py-2">
                <span class={[
                  "px-2 py-0.5 rounded text-xs",
                  run.status == "complete" && "bg-green-100 text-green-700",
                  run.status == "running" && "bg-yellow-100 text-yellow-700",
                  run.status == "pending" && "bg-gray-100 text-gray-700",
                  run.status == "error" && "bg-red-100 text-red-700"
                ]}>
                  {run.status}
                </span>
              </td>
              <td class="py-2 text-right">{run.user_count}</td>
              <td class="py-2 text-right">{run.edge_count}</td>
              <td class="py-2 text-right">{run.community_count}</td>
              <td class="py-2 text-right">{run.leiden_resolution}</td>
            </tr>
          </tbody>
        </table>
        <p :if={@runs == []} class="text-gray-500 py-4">No pipeline runs yet.</p>
      </div>
    </div>
    """
  end
end
