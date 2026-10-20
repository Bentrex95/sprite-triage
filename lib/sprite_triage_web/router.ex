defmodule SpriteTriageWeb.Router do
  use Phoenix.Router
  import Phoenix.Controller
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug SpriteTriageWeb.AccessKey

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; object-src 'none'; frame-ancestors 'none'"
    }

    plug :put_root_layout, html: {SpriteTriageWeb.Layouts, :root}
  end

  scope "/" do
    pipe_through :browser
    live "/", SpriteTriageWeb.TriageLive
  end
end
