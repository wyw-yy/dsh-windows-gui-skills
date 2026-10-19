# What is worth asking vs. not, by domain

**This file is advisory.** It records what actually happened when I asked (or did not ask).
It never overrides the current conversation, the user's explicit instruction, or AGENTS.md.
Anything older than 90 days is treated as stale.

Rule of thumb: a record here raises or lowers my prior; it does not decide the turn.

| Domain | Pattern observed | Advice |
|---|---|---|
| `embedded` (Keil / CubeMX / 烧录) | Almost every wrong turn came from an unstated hardware fact: board model, LED pin, crystal frequency, which probe, and whether I am allowed to flash. | **Worth 2–3 questions before touching hardware.** Cheap: one line each, and the answers do not change. |
| `github` (建仓 / 发版 / token) | Asking "public or private, owner, repo name" costs 10 seconds; guessing costs a force-push or a wrong account. | **Worth asking** when the target repo is not already obvious from context. |
| `gui-automation` (QQ / LCEDA / CubeMX) | The expensive mistakes were *not* ambiguities — they were coordinate drift, window rebuilds, popups. Questions did not help; verification did. | **Ask little here.** Ask one: "may I take over the mouse / may I send this?" Then work. |
| `skill-distribution` | Wrapping the whole thing as a plugin was speculative work the user later cancelled ("先不作为插件上传"). | **Worth asking first**: "zip 还是插件？给谁用？" before building packaging. |
| `refactor / code` | "优化一下" splits into readability vs speed vs size; that one question is nearly always worth it. | **Worth one question.** |
| `pure question` ("为什么…", "怎么看…") | Never once needed a clarifying question. | **Do not ask**, answer. |
| `read-only` (list / read / screenshot) | Asking permission for a read is pure friction. | **Do not ask.** |
| `already-answered` | Re-asking the same thing twice destroyed trust. | **Never re-ask**; re-read the thread first. |

## Observations from this machine (2026-10)

- The user says **"你先回答/先别动手"** when they want discussion, and **"你决定/全自动"** when they want no questions. Honour both directions immediately.
- For GUI work the user cares about *capability* (can you actually click it), not about being consulted — over-asking there reads as stalling.
- For hardware and publishing, the user expects me to ask, because a wrong guess burns time or touches other people.
