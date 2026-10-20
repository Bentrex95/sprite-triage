defmodule Mix.Tasks.SpriteTriage.Demo do
  @shortdoc "Run the web page against a simulated Sprites API (no account, no Fly calls)"
  @moduledoc """
      mix sprite_triage.demo            # prints http://localhost:4090/?key=…

  In a container set SPRITE_TRIAGE_IP=0.0.0.0. For a public demo (fly.toml) also set
  SPRITE_TRIAGE_PUBLIC_DEMO=true: then the page needs no key. That is only allowed here,
  where no real token exists.
  """
  use Mix.Task

  @impl true
  def run(_argv) do
    # Load config/runtime.exs first (IP, host, public flag), then the demo settings.
    Mix.Task.run("app.config")
    endpoint = Application.get_env(:sprite_triage, SpriteTriageWeb.Endpoint, [])

    Application.put_env(
      :sprite_triage,
      SpriteTriageWeb.Endpoint,
      Keyword.merge(endpoint, server: true)
    )

    Application.put_env(:sprite_triage, :api_options, SpriteTriage.Demo.api_options())

    # The simulated Sprites have no past: every demo starts with an empty history.
    demo_dir = Path.join(System.tmp_dir!(), "sprite-triage-demo")
    File.rm_rf!(demo_dir)
    Application.put_env(:sprite_triage, :data_dir, demo_dir)

    Mix.Task.run("app.start")
    Mix.shell().info("sprite-triage demo uses a simulated API; nothing is sent to Fly.")
    Process.sleep(:infinity)
  end
end
