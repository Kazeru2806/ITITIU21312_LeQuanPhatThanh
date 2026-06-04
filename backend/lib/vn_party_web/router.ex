defmodule VnPartyWeb.Router do
  use VnPartyWeb, :router

  pipeline :api do
	plug :accepts, ["json"]
  	plug CORSPlug, origin: [
    	"https://vn-party-thesis.vercel.app",
    	"https://vn-party-thesis-host-2bjn9x6y1-kazs-projects-a81dd6d8.vercel.app",
    	"https://vn-party-thesis-host.vercel.app"
  	]
  end

  scope "/api", VnPartyWeb do
    pipe_through :api

    post "/rooms", RoomController, :create
    get "/rooms/:code", RoomController, :show
    post "/rooms/:code/join", RoomController, :join
    get "/rooms/:code/players", RoomController, :list_players
    get "/rooms/:code/audit", RoomController, :audit

    get "/telemetry/latency.csv", TelemetryController, :latency_csv
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:vn_party, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: VnPartyWeb.Telemetry
    end
  end
end
