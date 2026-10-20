defmodule SpriteTriage.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # Demo mode (SPRITE_TRIAGE_DEMO=true): the simulated API, no token.
    if Application.get_env(:sprite_triage, :demo, false),
      do: Application.put_env(:sprite_triage, :api_options, SpriteTriage.Demo.api_options())

    SpriteTriageWeb.AccessKey.setup!()

    children =
      [
        {Task.Supervisor, name: SpriteTriage.TaskSupervisor},
        {Phoenix.PubSub, name: SpriteTriage.PubSub}
      ] ++
        if(Application.get_env(:sprite_triage, :web, true),
          do: [SpriteTriageWeb.Endpoint],
          else: []
        )

    result =
      Supervisor.start_link(children, strategy: :one_for_one, name: SpriteTriage.Supervisor)

    if server?(), do: IO.puts("sprite-triage on #{SpriteTriageWeb.AccessKey.url()}")
    result
  end

  defp server? do
    Application.get_env(:sprite_triage, :web, true) and
      Keyword.get(
        Application.get_env(:sprite_triage, SpriteTriageWeb.Endpoint, []),
        :server,
        false
      )
  end
end
