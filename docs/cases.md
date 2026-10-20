# Cases behind the rules

Public threads in the Fly.io community forum and issues in superfly/sprites-docs, read on 20 Oct 2026. "Staff confirmed" means a Fly employee named the cause or the fix in the thread. Sprite ids and organization names are left out.

| Thread | What the user saw | State | What helped |
|---|---|---|---|
| [28383](https://community.fly.io/t/28383) | sessions and checkpoints: `Client.Timeout exceeded while awaiting headers`; exec: `failed to connect: read tcp …: i/o timeout` | control_only | staff: `POST /v1/sprites/{name}/restart`; files stay, the agent process is ended |
| [28387](https://community.fly.io/t/28387) | exec `i/o timeout`, sessions time out | control_only | the user: restart worked |
| [28425](https://community.fly.io/t/28425) | sessions `context deadline exceeded`; restart and upgrade from the dashboard had no effect | control_only | not reported |
| [28474](https://community.fly.io/t/28474) | restart refused: "machine is stopping … try again in a moment" | (transition) | back after 5–10 minutes |
| [28561](https://community.fly.io/t/28561) | metadata fine, status `warm`; exec `i/o timeout`; console hangs; fs write times out; restart: `upstream restart failed` | control_only | no answer in the thread |
| [28655](https://community.fly.io/t/28655) | exec `i/o timeout`, restart times out | control_only | worked again after 20–30 minutes; staff applied a fix |
| [28659](https://community.fly.io/t/28659) | metadata fine, status `cold`; exec `i/o timeout`; restart `upstream restart failed`; later `service temporarily unavailable, please retry` | control_only | staff moved the Sprite; name hashes first pointed to the wrong one |
| [28696](https://community.fly.io/t/28696) | status `cold`; `GET /check`: `unhealthy`, `failed to start machine`; exec 502; restart 502 | start_failed | by the time staff looked it was "alive" |
| [28832](https://community.fly.io/t/28832) | `/check`: `failed to start machine` (twice); restart 409 `upstream restart conflict`, `retryable=true` | start_failed | staff confirmed: the host had no capacity and automatic replacement missed it |
| [28785](https://community.fly.io/t/28785) | `failed to start sprite command: Storage not ready`, again after a move | storage_not_ready | only moves by support; restart, upgrade and waiting did not help |
| [28798](https://community.fly.io/t/28798) | `Storage not ready` after the upgrade from rc48 to 0.0.2 | storage_not_ready | staff re-ran the upgrade |
| [28835](https://community.fly.io/t/28835) | checkpoint create: `503 Storage not ready` with a fly-request-id; 20 hours; restart, update and waiting without effect | storage_not_ready | staff moved it to another host |
| [28384](https://community.fly.io/t/28384) | checkpoint list: `500 … overlay manager not configured`; staff: data corruption at start | storage | staff: restore a working checkpoint, else support |
| [28492](https://community.fly.io/t/28492) | checkpoint list 500 `overlay manager not configured`; restore failed twice, worked the third time | storage | retrying hours later |
| [28240](https://community.fly.io/t/28240) | exec fails at the WebSocket upgrade for days | control_only | staff "unwedged" it by hand; cause: open file descriptors kept growing |
| [28728](https://community.fly.io/t/28728) | the automatic checkpoint already contained the corruption | – | staff picked an older checkpoint |
| [sprites-docs#230](https://github.com/superfly/sprites-docs/issues/230) | storage wedged while the VM stays `running`; all I/O, /checkpoints and /services hang | control_only | only destroying the Sprite |
| [sprites-docs#231](https://github.com/superfly/sprites-docs/issues/231) | no data-preserving recovery; one hung request keeps the Sprite busy | – | – |

Staff asked for the Sprite name, the organization and "a few fly-request-ids" ([28774](https://community.fly.io/t/28774)), and explained in [28288](https://community.fly.io/t/28288) that `cold` Sprites are usually suspended, so the status says little about memory.
