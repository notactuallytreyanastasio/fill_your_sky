defmodule FillTheSky.ML.PythonWorker do
  @moduledoc """
  GenServer that serializes all Pythonx calls.
  Python's GIL means concurrent calls are pointless — this ensures
  one ML job runs at a time.
  """

  use GenServer

  require Logger

  @type state :: %{busy: boolean()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  @spec run_pipeline(map()) :: {:ok, map()} | {:error, term()}
  def run_pipeline(params) do
    GenServer.call(__MODULE__, {:run_pipeline, params}, :infinity)
  end

  # --- GenServer callbacks ---

  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(_opts) do
    {:ok, %{busy: false}}
  end

  @impl true
  def handle_call({:run_pipeline, params}, _from, %{busy: false} = state) do
    state = %{state | busy: true}
    result = execute_python(params)
    {:reply, result, %{state | busy: false}}
  end

  def handle_call({:run_pipeline, _params}, _from, %{busy: true} = state) do
    {:reply, {:error, :busy}, state}
  end

  # --- Private ---

  defp execute_python(params) do
    script_path = Path.join(:code.priv_dir(:fill_the_sky), "python/leiden_pipeline.py")

    try do
      {result, _} =
        Pythonx.eval(
          File.read!(script_path),
          %{
            "edges" => Jason.encode!(params.edges),
            "bios" => Jason.encode!(params.bios),
            "resolution" => params[:resolution] || 1.0,
            "n2v_dimensions" => params[:n2v_dimensions] || 64
          }
        )

      json_string = Pythonx.decode(result)

      case Jason.decode(json_string) do
        {:ok, decoded} -> {:ok, decoded}
        {:error, reason} -> {:error, {:json_decode, reason}}
      end
    rescue
      e -> {:error, {:python_error, Exception.message(e)}}
    end
  end
end
