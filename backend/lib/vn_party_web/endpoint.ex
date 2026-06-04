defmodule VnPartyWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :vn_party

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  @session_options [
    store: :cookie,
    key: "_vn_party_key",
    signing_salt: "your-signing-salt",
    same_site: "Lax"
  ]

  # Longpoll must stay enabled: Node loadgen (phoenix.js) falls back to GET /socket/longpoll
  # when the WebSocket path is unavailable; with longpoll: false those requests hit the Router
  # and raise Phoenix.Router.NoRouteError.
  socket "/socket", VnPartyWeb.UserSocket,
    websocket: true,
    longpoll: true

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :vn_party,
    gzip: false,
    only: VnPartyWeb.static_paths()

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options

  # CORS - Allow requests from frontend
  # In development, allow all origins for easier testing (including local network IPs)
  plug CORSPlug,
    origin: &VnPartyWeb.CORS.origin_allowed?/1,
    headers: ["Authorization", "Content-Type", "Accept", "Origin"],
    methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    max_age: 86400

  plug VnPartyWeb.Router
end
