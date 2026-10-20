defmodule Mix.Tasks.SpriteTriage do
  @shortdoc "Triage a Sprite that stopped answering"
  @moduledoc "See `SpriteTriage.CLI`. Reads the token from SPRITES_TOKEN."
  use Mix.Task

  @impl true
  def run(argv) do
    token = System.get_env("SPRITES_TOKEN")

    if is_nil(token) do
      Mix.shell().error("SPRITES_TOKEN is not set\n\n" <> SpriteTriage.CLI.usage())
      exit({:shutdown, 2})
    end

    Mix.Task.run("app.config")
    Application.put_env(:sprite_triage, :web, false)
    Mix.Task.run("app.start")

    {code, output} = SpriteTriage.CLI.main(argv, token: token)
    if code == 2, do: Mix.shell().error(output), else: Mix.shell().info(output)
    exit({:shutdown, code})
  end
end
