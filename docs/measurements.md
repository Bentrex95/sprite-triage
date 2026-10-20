# First checks after a quiet period

Measured on 20 October 2026 with an earlier version of sprite-triage (then `--json --wake`) against
7 Sprites created for the test in a trial organization. Each Sprite was left alone for at least
15 minutes, then triaged once; about two minutes later it was triaged again. Organization, Sprite ids and
request ids are left out.

| # | Sprite | First check (UTC) | `/check` answer | `/check` ms | Command inside | About two minutes later |
|---|---|---|---|---|---|---|
| 1 | triage-test-1 | 2026-10-20 08:34:57 | 200 needs_repair: machine in suspended state | 755 | ok, 996 ms | healthy (machine is running), command ok |
| 2 | triage-test-2 | 2026-10-20 08:37:05 | 200 needs_repair: machine in suspended state | 874 | ok, 1015 ms | healthy (machine is running), command ok |
| 3 | triage-test-3 | 2026-10-20 08:39:13 | 200 needs_repair: machine in suspended state | 741 | ok, 11156 ms | healthy (machine is running), command ok |
| 4 | triage-test-4 | 2026-10-20 08:41:32 | 200 needs_repair: machine in suspended state | 942 | ok, 1180 ms | healthy (machine is running), command ok |
| 5 | triage-more-1020-01-01 | 2026-10-20 08:42:26 | 200 needs_repair: machine in suspended state | 802 | ok, 872 ms | healthy (machine is running), command ok |
| 6 | triage-test-5 | 2026-10-20 08:43:40 | 200 needs_repair: machine in suspended state | 1066 | ok, 1538 ms | healthy (machine is running), command ok |
| 7 | triage-test-1 | 2026-10-20 09:02:52 | 200 needs_repair: machine in suspended state | 840 | ok, 1015 ms | healthy (machine is running), command ok |
| 8 | triage-test-2 | 2026-10-20 09:02:56 | 200 needs_repair: machine in suspended state | 795 | ok, 1289 ms | healthy (machine is running), command ok |
| 9 | triage-test-3 | 2026-10-20 09:05:06 | 200 needs_repair: machine in suspended state | 946 | ok, 2066 ms | healthy (machine is running), command ok |
| 10 | triage-test-4 | 2026-10-20 09:07:15 | 200 needs_repair: machine in suspended state | 1018 | ok, 1661 ms | healthy (machine is running), command ok |
| 11 | triage-test-5 | 2026-10-20 09:09:24 | 200 needs_repair: machine in suspended state | 1021 | ok, 968 ms | healthy (machine is running), command ok |
| 12 | triage-test-1 | 2026-10-20 09:26:36 | 200 needs_repair: machine in suspended state | 1137 | ok, 955 ms | healthy (machine is running), command ok |
| 13 | triage-test-2 | 2026-10-20 09:28:44 | 200 needs_repair: machine in suspended state | 850 | ok, 1022 ms | healthy (machine is running), command ok |
| 14 | triage-test-3 | 2026-10-20 09:30:53 | 200 needs_repair: machine in suspended state | 758 | ok, 1643 ms | healthy (machine is running), command ok |
| 15 | triage-test-4 | 2026-10-20 09:33:02 | 200 needs_repair: machine in suspended state | 808 | ok, 1820 ms | healthy (machine is running), command ok |
| 16 | triage-test-5 | 2026-10-20 09:35:12 | 200 needs_repair: machine in suspended state | 898 | ok, 1025 ms | healthy (machine is running), command ok |
| 17 | triage-workload-1020-1e4e60de | 2026-10-20 09:38:58 | 200 needs_repair: machine in suspended state | 916 | ok, 972 ms | healthy (machine is running), command ok |
| 18 | triage-workload-1020-1e4e60de | 2026-10-20 09:56:10 | 200 needs_repair: machine in suspended state | 993 | ok, 1052 ms | healthy (machine is running), command ok |

All 18 first checks answered `needs_repair: machine in suspended state` while the command inside ran; all 18
checks two minutes later were healthy. The version measured here turned each first check into `unknown` with a
support note. sprite-triage now reads this answer as a Sprite waking up when the command inside runs.

## Rerun with the current version

On 20 October 2026, commit `4a11136`, three new Sprites: triaged fresh (3/3 `ok`, no note), left alone for
15 minutes, then triaged again. The first `/check` answered the same way, the command inside ran, and the result
was `ok` without a support note. A text-mode triage after another 15 quiet minutes also gave `ok` without a note.

| # | Sprite | First check (UTC) | `/check` answer | `/check` ms | Command inside | Result |
|---|---|---|---|---|---|---|
| 1 | triage-v2-1 | 2026-10-20 14:21:49 | 200 needs_repair: machine in suspended state | 1280 | ok, 985 ms | `ok`, no note |
| 2 | triage-v2-2 | 2026-10-20 14:22:00 | 200 needs_repair: machine in suspended state | 948 | ok, 1134 ms | `ok`, no note |
| 3 | triage-v2-3 | 2026-10-20 14:22:10 | 200 needs_repair: machine in suspended state | 868 | ok, 1100 ms | `ok`, no note |
