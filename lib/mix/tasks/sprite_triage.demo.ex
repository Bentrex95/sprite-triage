defmodule Mix.Tasks.SpriteTriage.Demo do
  @shortdoc "Run the web page against a simulated Sprites API (no account, no Fly calls)"
  @moduledoc """
      mix sprite_triage.demo            # prints http://localhost:4090/?key=…

  The same as starting with SPRITE_TRIAGE_DEMO=true and SPRITE_TRIAGE_SERVER=true, which
  is what the Docker image does. In a container set SPRITE_TRIAGE_IP=0.0.0.0. A public
  demo also sets SPRITE_TRIAGE_PUBLIC_DEMO=true: then the page needs no key. That is only
  allowed in demo mode, where no real token exists.
  """
  use Mix.Task

  @impl true
  def run(_argv) do
    System.put_env("SPRITE_TRIAGE_DEMO", "true")
    System.put_env("SPRITE_TRIAGE_SERVER", "true")
    Mix.Task.run("app.start")
    Mix.shell().info("sprite-triage demo uses a simulated API; nothing is sent to Fly.")
    Process.sleep(:infinity)
  end
end
