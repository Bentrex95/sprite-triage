# sprite-triage

When a Sprite stops answering, sprite-triage checks the few signals the API offers, runs one command inside the Sprite, says what the results point to, lists the next steps that helped in public forum threads (and the ones that made things worse), and writes the short note Fly support asks for. It restarts nothing and changes no settings; its checks can wake a sleeping Sprite. It has a small Phoenix LiveView page and a command line (text or JSON).

## Why

Between July and October 2026 the Fly.io community forum collected more than fifteen threads about stuck Sprites ([cases](docs/cases.md)). They go the same way: `GET /v1/sprites/{name}` works, but exec, console and checkpoints hang or fail with `i/o timeout` or `Storage not ready`; people try restarts, upgrades and waiting, often in loops; then support asks for the Sprite id, the organization, `fly-request-id` values and the time it started failing, piece by piece. One user asked for "the right set of steps for us to perform" ([28835](https://community.fly.io/t/28835)).

Only Fly can fix the host side. A tool can shorten the way there and keep people and agents from making things worse.

Fly's monitoring (log export, metrics) covers apps on Machines and needs the instance to emit something; its docs do not mention Sprites. A stuck Sprite emits nothing, it just stops answering. sprite-triage asks from the outside, at that moment, for one Sprite.

How this problem was chosen over six other ideas: [how it came about](docs/how-it-came-about.md).

## Try it without an account

```sh
docker build -t sprite-triage-demo . && docker run --rm -p 127.0.0.1:4090:4090 sprite-triage-demo
```

Then open http://localhost:4090/. With Elixir 1.18+ installed, `mix deps.get && mix sprite_triage.demo` does the same, and `SPRITE_TRIAGE_DEMO=true mix sprite_triage demo-wedged` tries the command line. A simulated API replays five patterns: `demo-healthy`, `demo-waking` (the first wake after a quiet period, see below), `demo-wedged` (healthy `/check`, but a command inside hangs), `demo-storage` and `demo-start-failed`. The image runs on Fly.io as it is; `fly.toml` lists the three commands.

![Triage of a wedged Sprite in demo mode](docs/triage-wedged.png)

## Use it

```sh
export SPRITES_TOKEN=...
mix sprite_triage my-sprite            # text
mix sprite_triage my-sprite --json     # JSON
SPRITE_TRIAGE_SERVER=true mix run --no-halt   # the page; prints its address with a key
```

Exit codes: 0 the Sprite answers, 1 it does not or the signals are unclear, 2 usage, token or name problem. The page uses your token, so it listens on 127.0.0.1 and needs the key it prints at start.

## What it checks

| Probe | When | Effect on the Sprite |
|---|---|---|
| `GET /v1/sprites/{name}` | always | none |
| `GET /v1/sprites/{name}/check` | always | may wake it; reports `failed to start machine` or `Storage not ready` |
| one exec of `true` | when `/check` answered healthy or suspended | wakes it; run once, never retried |

The HTTP probes run in parallel with deadlines (15 s, 60 s); the exec gets 45 s. A probe that runs over is killed. The exec command belongs to a guard process that kills it at the deadline, even if the SDK hands it over late; a connect that never returns at all stays the SDK's to close. Nothing is retried, and when `/check` already failed no command is sent: a hung call keeps a stuck Sprite busy.

| State | Meaning | Next step |
|---|---|---|
| `ok` | `/check` answered and the command ran | nothing to fix on the Sprite |
| `control_only` | the API answers, the Sprite does not | stop traffic, one restart as staff advised, then support |
| `start_failed` | `/check`: failed to start | support; restarts failed in both reports |
| `storage_not_ready` | "Storage not ready" | support; only Fly fixed it |
| `unknown_network` | the API did not answer | check your network and the status page |
| `unknown`, `auth_error`, `not_found` | contradicting signals, token or name | as shown |

The reported status (`running`, `warm`, `cold`) is shown but never used: stuck Sprites were reported with each of the three, and a healthy one as `cold`. Every step on the page names the thread it comes from and where it did not help.

## Measured on real Sprites

On 20 October 2026 an earlier version ran against Sprites created for the test in a trial organization. After a quiet period, the first `/check` answered HTTP 200 with `{"status": "needs_repair", "reason": "machine in suspended state"}` in 18 of 18 cases on seven Sprites, while `true` inside ran (in 0.9 to 11 s). Two minutes later all 18 were healthy ([table](docs/measurements.md)). That version reported these as `unknown` with a support note: 18 false alarms. Now the command inside decides. A rerun with the current version on three new Sprites gave the same `/check` answer on 3 of 3 first checks after 15 quiet minutes, and `ok` without a note each time. I could not find this answer in the Sprites docs, the OpenAPI spec or the Elixir SDK.

## Limits

- It has not met a really stuck Sprite. Those cannot be made on purpose; the rules come from public threads, and the deadlines are estimates from them.
- `/check` is not in the public OpenAPI or the Elixir SDK; it comes from the official JS SDK and staff answers. Its full set of answers is not documented.
- `mix deps.get` reports advisories for cowlib 2.19 and gun 2.5, which the Sprites Elixir SDK pins. They concern cookie, Link and structured-header encoding; sprite-triage sends no cookies and builds no such headers. One of them (CVE-2026-43966) has no fixed release yet.

## How it is tested

`mix test` takes about 15 seconds. The classifier is checked against cases rebuilt from the forum threads and the measurements above; the probes run against stubbed HTTP with real tasks and deadlines, the exec through its real guard with the SDK call replaced; the page is tested state by state. `scripts/verify.sh` adds the format and warning checks and builds and starts the demo image.

## Decisions

- No restart button. The most common finding, a Sprite waking up, needs no restart, and a triage tool should read, not act. The advice says when one restart is worth a try, and the person does it.
- The command inside runs by default. In the most common stuck pattern the API and the VM looked fine while every command hung; the threads do not say what `/check` answered then, so the command decides. On waking Sprites it was also what told them apart from stuck ones.
- No "failing since" from local logs. Only the person knows when it started; the note asks for it.
- No HTTP retries. A stuck Sprite gets one request per probe (sprites-docs#231).

## Code

```
lib/sprite_triage/classify.ex     observations -> state (pure)
lib/sprite_triage/advice.ex       state -> do / don't, with sources (pure)
lib/sprite_triage/note.ex         support note and its age (pure)
lib/sprite_triage/probe.ex        probes with deadlines
lib/sprite_triage/exec.ex         the exec of `true`, owned by a guard process
lib/sprite_triage/api.ex          HTTP calls, fly-request-id, no retries
lib/sprite_triage/cli.ex          the command line as a function
lib/sprite_triage/demo.ex         the simulated API
lib/sprite_triage_web/            the page and its access key
```

Built with coding agents: Claude Code wrote most of the code, Codex reviewed it independently. I picked the problem from the forum data, set the rules and the checks, ran it against real Sprites and decided what to cut.
