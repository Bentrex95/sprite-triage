defmodule SpriteTriage.Advice do
  @moduledoc """
  What to do next for each state. Pure data, no I/O.

  Every step names where it comes from (a staff answer, an issue, the docs, or our own
  measurements) and, where one exists, a case in which it did not help. The list is
  deliberately short: most self-help steps people try in the forum threads (upgrade,
  repeated restarts, restoring the newest checkpoint) either did nothing or made things
  worse.

  sprite-triage never restarts anything itself. Where a restart is worth one try, the
  advice says so and the person does it.
  """

  @forum "https://community.fly.io/t/"
  @docs_issue "https://github.com/superfly/sprites-docs/issues/"
  # Not a link: our own measurements, described in the README.
  @measured "own measurements on real Sprites (README)"

  defp step(id, text, sources, counter \\ []),
    do: %{id: id, text: text, sources: sources, counter_sources: counter}

  defp dont(id, text, sources), do: %{id: id, text: text, sources: sources}

  defp stop_traffic,
    do:
      step(
        :stop_traffic,
        "Stop clients, agents and retry loops that call this Sprite. A hung request keeps it from pausing and leaves zombie exec sessions.",
        [@docs_issue <> "231", @docs_issue <> "230"]
      )

  defp keep_note,
    do:
      step(
        :keep_note,
        "Keep the support note below: Sprite id, organization, fly-request-id values and the time it started failing.",
        [@forum <> "28774"]
      )

  defp ask_support(extra, cases),
    do:
      step(
        :ask_support,
        "Contact Fly support (fly.io/dashboard/support) with the note below and ask them to preserve the filesystem and checkpoints." <>
          extra,
        Enum.map(cases, &(@forum <> &1)) ++ ["https://fly.io/dashboard/support"]
      )

  defp common_dont,
    do: [
      dont(:no_upgrade, "Don't upgrade the Sprite as a recovery step.", [
        @forum <> "28425",
        @forum <> "28785"
      ]),
      dont(
        :no_restore_newest,
        "Don't restore the newest checkpoint: an automatic checkpoint can contain the broken state, and a restore discards later changes.",
        [@forum <> "28728", @forum <> "28384"]
      ),
      dont(:no_destroy, "Don't destroy the Sprite to start over while you still need its data.", [
        @docs_issue <> "230"
      ]),
      dont(:no_loops, "Don't run exec or checkpoint calls in a loop to test it.", [
        @docs_issue <> "231"
      ])
    ]

  defp no_more_restarts,
    do:
      dont(
        :no_more_restarts,
        "Don't restart again and again: in the reports, repeated restarts did not help.",
        [@forum <> "28561", @forum <> "28696", @forum <> "28832"]
      )

  @spec for_state(atom()) :: %{do: [map()], dont: [map()], escalate: boolean()}
  def for_state(:control_only),
    do: %{
      do: [
        stop_traffic(),
        keep_note(),
        step(
          :restart_once,
          "Restart the Sprite once, from the dashboard or the API, as staff advised. Running processes and in-memory work are lost; files stay.",
          [@forum <> "28383", @forum <> "28387"],
          [@forum <> "28561", @forum <> "28659", @forum <> "28696", @forum <> "28832"]
        ),
        ask_support(" Do this if it is still stuck after that one restart.", [
          "28659",
          "28785",
          "28835"
        ])
      ],
      dont: [no_more_restarts() | common_dont()],
      escalate: false
    }

  def for_state(:start_failed),
    do: %{
      do: [
        stop_traffic(),
        keep_note(),
        ask_support(
          " In both reports restarts failed; in 28832 staff found the host had no capacity.",
          ["28696", "28832"]
        )
      ],
      dont: [
        dont(:no_restart, "Don't restart: it failed in both reports.", [@forum <> "28832"])
        | common_dont()
      ],
      escalate: true
    }

  def for_state(:storage_not_ready),
    do: %{
      do: [
        stop_traffic(),
        keep_note(),
        ask_support(
          " In the reports only Fly fixed this, by moving the Sprite or re-running its upgrade.",
          ["28785", "28798", "28835"]
        )
      ],
      dont: [
        dont(
          :no_waiting_game,
          "Don't expect restart, upgrade or waiting to fix it; they did not in the reports.",
          [@forum <> "28785", @forum <> "28835"]
        )
        | common_dont()
      ],
      escalate: true
    }

  def for_state(:waking),
    do: %{
      do: [
        step(
          :wait_and_recheck,
          "The Sprite was asleep and is waking up. Run the triage again in two minutes, or now with \"Also run true\" ticked. On real Sprites the first /check after a quiet period answered this way every time, and two minutes later it was healthy.",
          [@measured]
        )
      ],
      dont: [
        dont(:no_restart_waking, "Don't restart a Sprite that is only waking up.", [@measured])
      ],
      escalate: false
    }

  def for_state(:ok),
    do: %{
      do: [
        step(
          :check_client,
          "If your commands still hang, run the triage again with \"Also run true\" ticked: /check alone can look healthy while commands hang.",
          [@docs_issue <> "230"]
        )
      ],
      dont: [],
      escalate: false
    }

  def for_state(:unknown_network),
    do: %{
      do: [
        step(
          :check_own_network,
          "Check your own connection and https://status.flyio.net, then run the triage again from another network.",
          ["https://status.flyio.net"]
        )
      ],
      dont: [
        dont(:no_restart_blind, "Don't restart yet: nothing shows the Sprite is the problem.", [
          @forum <> "28659"
        ])
      ],
      escalate: false
    }

  def for_state(state) when state in [:auth_error, :not_found],
    do: %{
      do: [
        step(:check_token, "Check the token, the organization and the Sprite name.", [
          "https://docs.fly.io/sprites/"
        ])
      ],
      dont: [],
      escalate: false
    }

  def for_state(:unknown),
    do: %{do: [stop_traffic(), keep_note()], dont: common_dont(), escalate: false}
end
