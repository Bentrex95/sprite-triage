# How sprite-triage came about

## The question

In July Fly wrote that "Computers for Agents are, going forward, the focus of our company" ([Kurt Mackey](https://fly.io/blog/kurt-scott-money-sprites/)). So I asked where it breaks today between what an agent sets out to do on a Sprite and a result someone can rely on.

A first attempt measured what the `cold` status means. It found a real gap (a process survived a pause the docs say it should not), but it answered a question few people ask. I kept that as a draft fix for the docs and started again from what users report.

## What users report

I went through about 600 forum topics (April to October 2026) and the issues of the 35 superfly repositories with "sprite" in the name: 74 separate problems in 10 groups. The largest group is Sprites that stop answering. Reading the Sprite works, everything that touches the VM hangs or says `Storage not ready`; people try restarts, upgrades and waiting; support asks for the same facts one at a time; and users ask for steps they can take themselves ([28785](https://community.fly.io/t/28785), [28835](https://community.fly.io/t/28835)). The threads behind the rules are in [cases.md](cases.md).

## Choosing

Seven candidates, judged on: documented pain, buildable from outside with the public API, testable without a broken Sprite, not something Fly already ships, and fit for the role.

| Candidate | Outcome |
|---|---|
| Triage for a Sprite that stopped answering | built |
| Exec results that survive a dropped connection | backup |
| Checks before and after a checkpoint | later, as part of the triage |
| Cost per Sprite with a budget stop | dropped: cannot be checked from outside without a usage API |
| Preflight for agent tools in the base image | dropped: too narrow, outdated with each image |
| Credential broker with approvals | dropped: works against the sandbox as the boundary |
| Promoting a Sprite to a Machine | dropped: Fly has announced it |

## Agents first, a person at the edge

Fly's posts argue that agents do best with explicit state. So the result is a named state, the allowed next steps with their sources, exit codes and JSON for an agent; the page and the support note are for a person; and anything risky, a restart, is left to the person.

## How it was built

With coding agents: Claude Code wrote most of the code and Codex reviewed it independently. My part was the problem, the rules, what counts as done, the real-Sprite runs and what to cut. Each change had to pass the tests, and rules were broken on purpose to see that a named test catches them. Three times the repository was graded cold against a rubric taken from what Fly says it values, and each round fed the next set of cuts.

## What real Sprites changed

The first run against real Sprites turned 18 healthy first checks after a quiet period into support notes, because `/check` answered `needs_repair` while the Sprite was only waking up. Since then one command inside decides; the rerun gave `ok` on 3 of 3 ([measurements](measurements.md)). What was cut along the way is under Decisions in the [README](../README.md#decisions).
