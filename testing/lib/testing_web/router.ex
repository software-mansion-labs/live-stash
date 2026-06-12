defmodule TestingWeb.Router do
  use TestingWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TestingWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TestingWeb do
    pipe_through :browser

    get "/", PageController, :home

    live "/test/counter/live_stash_server", LiveStashServerCounterLive
    live "/test/counter/live_stash_client", LiveStashClientCounterLive
    live "/test/counter/live_stash_redis", LiveStashRedisCounterLive
    live "/test/counter/live_stash_mnesia", LiveStashMnesiaCounterLive

    live "/performance/baseline", Performance.BaselineLive
    live "/performance/livestash_ets", Performance.LiveStashEtsLive
    live "/performance/livestash_browser_memory", Performance.LiveStashBrowserMemoryLive
    live "/performance/livestash_redis", Performance.LiveStashRedisLive
    live "/performance/livestash_mnesia", Performance.LiveStashMnesiaLive
  end

  scope "/test/mnesia", TestingWeb do
    pipe_through :api

    get "/info", MnesiaClusterController, :info
    post "/simulate-inconsistency", MnesiaClusterController, :simulate_inconsistency
    post "/poison", MnesiaClusterController, :poison
  end

  # Other scopes may use custom stacks.
  # scope "/api", TestingWeb do
  #   pipe_through :api
  # end
end
