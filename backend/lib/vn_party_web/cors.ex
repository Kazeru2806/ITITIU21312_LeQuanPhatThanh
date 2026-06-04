defmodule VnPartyWeb.CORS do
  @moduledoc false

  @static_origins [
    "http://localhost:5173",
    "http://localhost:5174",
    "http://localhost:5175",
    "https://vn-party-thesis.vercel.app",
    "https://vn-party-thesis-host.vercel.app"
  ]

  def origin_allowed?(origin) when is_binary(origin) do
    extra =
      case System.get_env("ALLOWED_ORIGINS") do
        nil -> []
        "" -> []
        csv -> String.split(csv, ",", trim: true)
      end

    allowed = @static_origins ++ extra

    origin in allowed or vercel_preview_origin?(origin)
  end

  def origin_allowed?(_), do: false

  defp vercel_preview_origin?(origin) do
    String.starts_with?(origin, "https://") and String.ends_with?(origin, ".vercel.app")
  end
end
