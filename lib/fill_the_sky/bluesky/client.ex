defmodule FillTheSky.Bluesky.Client do
  @moduledoc """
  HTTP client for the Bluesky AT Protocol public API.
  Uses Req for HTTP requests against public.api.bsky.app.
  No authentication required for read endpoints.
  """

  @base_url "https://public.api.bsky.app/xrpc"

  @type cursor :: String.t() | nil
  @type api_result :: {:ok, map()} | {:error, term()}

  @spec get_follows(String.t(), cursor()) :: api_result()
  def get_follows(actor, cursor \\ nil) do
    params = [actor: actor, limit: 100] ++ cursor_param(cursor)
    get("app.bsky.graph.getFollows", params)
  end

  @spec get_followers(String.t(), cursor()) :: api_result()
  def get_followers(actor, cursor \\ nil) do
    params = [actor: actor, limit: 100] ++ cursor_param(cursor)
    get("app.bsky.graph.getFollowers", params)
  end

  @spec get_profiles(list(String.t())) :: api_result()
  def get_profiles(actors) when is_list(actors) and length(actors) <= 25 do
    params = Enum.map(actors, &{:actors, &1})
    get("app.bsky.actor.getProfiles", params)
  end

  @spec get_profile(String.t()) :: api_result()
  def get_profile(actor) do
    get("app.bsky.actor.getProfile", actor: actor)
  end

  @spec get_author_feed(String.t(), cursor()) :: api_result()
  def get_author_feed(actor, cursor \\ nil) do
    params = [actor: actor, limit: 100] ++ cursor_param(cursor)
    get("app.bsky.feed.getAuthorFeed", params)
  end

  @spec resolve_handle(String.t()) :: api_result()
  def resolve_handle(handle) do
    get("com.atproto.identity.resolveHandle", handle: handle)
  end

  # --- Private ---

  defp get(method, params) do
    url = "#{@base_url}/#{method}"

    case Req.get(url, params: params, retry: :transient, max_retries: 3) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp cursor_param(nil), do: []
  defp cursor_param(cursor), do: [cursor: cursor]
end
