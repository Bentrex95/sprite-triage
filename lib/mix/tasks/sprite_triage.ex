defmodule Mix.Tasks.SpriteTriage do
  @shortdoc "Triage a Sprite that stopped answering"
  @moduledoc """
  See `SpriteTriage.CLI`. Reads the token from SPRITES_TOKEN. With SPRITE_TRIAGE_DEMO=true
  it asks the simulated API instead and needs no token:

      SPRITE_TRIAGE_DEMO=true mix sprite_triage demo-wedged
  """
  use Mix.Task

  @impl true
  def run(argv) do
    demo = System.get_env("SPRITE_TRIAGE_DEMO") == "true"
    token = System.get_env("SPRITES_TOKEN")

    if is_nil(token) and not demo do
      Mix.shell().error("SPRITES_TOKEN is not set\n\n" <> SpriteTriage.CLI.usage())
      exit({:shutdown, 2})
    end

    Mix.Task.run("app.config")
    Application.put_env(:sprite_triage, :web, false)
    Mix.Task.run("app.start")

    api = if demo, do: SpriteTriage.Demo.api_options(), else: [token: token]
    {code, output} = SpriteTriage.CLI.main(argv, api)
    if code == 2, do: Mix.shell().error(output), else: Mix.shell().info(output)
    exit({:shutdown, code})
  end
end
