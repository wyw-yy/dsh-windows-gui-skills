---
name: clarify-before-act
description: >-
  Ask a short, high-value set of questions before starting work that is ambiguous, irreversible, or expensive — then execute without further interrogation. Use at the start of any non-trivial request: creating or changing files/projects, sending messages or email, deleting or overwriting, installing software, spending money, flashing hardware, or any task whose target, scope, or acceptance criteria could reasonably mean two different things. Also use when the user says 先问我 / 每次先确认 / 别急着动手 / ask me first / confirm before you start / check with me.
---

# Clarify before you act

The goal is **one round of questions, then uninterrupted work** — not a conversation.
A good question costs 10 seconds and saves a wasted hour; a bad question costs trust.

## 1. Ten-second triage

Before the first tool call, answer three things silently:

1. **What does "done" look like?** If you cannot state it in one sentence, ask.
2. **What is irreversible?** Sending, deleting, flashing, paying, publishing, overwriting.
3. **What would I have to guess?** Path, target, credentials, device, format, deadline.

Ask if any answer is "I don't know" **and** a wrong guess is expensive.
Proceed if a wrong guess is cheap and reversible — then say what you assumed.

## 2. Ask when (any one is enough)

- **Two readings**: the request supports two materially different deliverables
  ("整理一下这个项目" could be docs, refactor, or cleanup).
- **Irreversible**: it sends/publishes/deletes/flashes/pays, or touches someone else's data.
- **Missing input you cannot invent**: credentials, account, board model, file, URL, target person.
- **Placement**: where files should live, which repo/branch, which machine.
- **Scope vs time**: the ask implies hours of work but the user expects minutes.
- **Acceptance**: "好不好" is subjective — ask what would make them say "对了".
- **Shared state**: the work touches something the user is actively using (their mouse, their editor, their open chat).

## 3. Do NOT ask when

- The user asked a question and wants an answer, not a plan. Answer first.
- The request is already specific enough to satisfy in one obvious way.
- The action is read-only: listing, reading, searching, screenshotting.
- The user already said "你决定" / "随便" / "just do it" / "全自动".
- You are mid-task and the next step is implied by the plan you already stated.
- You would be asking for permission to do the thing they just asked for.

Never re-ask something already answered earlier in the thread. Re-read before asking.

## 4. The five slots

Cover only the slots that actually matter for this task; skip the rest.

| Slot | Question shape | Example |
|---|---|---|
| **Goal** | "你想要的最终产物是 A 还是 B？" | 截图 / 可复现脚本 / 一份报告 |
| **Boundary** | "哪些不要动？" | 只改 `App/`，别碰 CubeMX 生成的文件 |
| **Authority** | "这一步我可以直接做吗？" | 发消息 / 删文件 / 装软件 / 烧录 |
| **Acceptance** | "怎样算成功？" | 灯在闪 / 串口有这行输出 / 文件能打开 |
| **Cost** | "花 30 分钟可以吗？" | 快糙方案 vs 完整方案 |

## 5. Question budget and format

- **At most 3 questions, one round.** More than 3 means the task is underspecified — ask
  the one question that unblocks the rest, or propose a plan with stated assumptions.
- **Each question carries a recommendation.** "A（推荐）: … / B: …" beats an open field.
- **Batch them.** Use `ask_user_question` with 2–4 options per question, recommended first.
- **Never ask what a tool can tell you.** Check the file, the process list, the git log first;
  a question that a `Get-ChildItem` would have answered reads as laziness.

Question that works:

> 目标确认一下（选一个就行）：
> - **A（推荐）** 只做能跑的最小版本，今天交付
> - **B** 完整版，含文档和测试，明天给
> 另外：产物放 `deep32\` 还是你指定的目录？

Question that fails:

> 你能详细说说你想要什么吗？

## 6. Assumption ledger (when you choose not to ask)

State assumptions in one compact block **before** acting, and make them cheap to correct:

```
假设（不对就说一声，我改）：
1. 目标板是 STM32F401RCT6，LED 在 PA11
2. 外部晶振 8 MHz，最终 84 MHz
3. 只生成工程，不代烧
```

Then proceed. Do not wait for approval on reversible assumptions.

## 7. After the answers

1. **Restate the contract in one line** — "好，A 方案：改 `App/`，不动 CubeMX 生成的，2 小时内给你能跑的版本。"
2. **Then work without further check-ins**, unless a new irreversible step appears.
3. If reality contradicts an answer (file missing, device absent), report it and pick the
   fallback you already named — don't restart the questionnaire.

## 8. Anti-patterns

- **Interrogation**: 6 questions before touching anything. The user wanted work, not a form.
- **Permission theatre**: asking "可以开始吗？" for what they already asked for.
- **Fake choice**: offering A/B when one is obviously wrong.
- **Asking after acting**: questions are cheap before, excuses are expensive after.
- **Silent guessing on irreversible steps**: never send/delete/flash on an assumption.
- **Re-asking**: same question twice in a session destroys credibility.

## 9. Worked examples

**"帮我把这个技能发给别人"**
Ask: 发给谁（同事 / 公开仓库）？ 形态（zip / 一条命令 / npm）？ — 2 questions, then do it.

**"烧录一下"**
Ask only if the target is ambiguous (which board / which firmware). If the project and probe
are already known from context, flash and report the log markers.

**"优化一下这段代码"**
Ask: 优化目标（可读性 / 速度 / 体积）？ 允许改接口吗？ — then measure before/after.

**"随便聊聊" / "你怎么看"**
Ask nothing. Answer.

## 10. Knowledge base (advisory only)

The skill keeps a small local memory of *how asking went*, so the same mistake is not repeated.
It is **evidence, never a rule** — it never blocks work and never overrides the current thread.

```
scripts\clarify.ps1        # Add-ClarifyRecord / Get-ClarifyStats / Get-ClarifyAdvice
data\clarify-log.json      # append-only records, last 500 kept
data\clarify-knowledge.md  # hand-written "worth asking vs not" table by domain
```

Load it (each PowerShell call is a new process):

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
. "$env:USERPROFILE\.agents\skills\clarify-before-act\scripts\clarify.ps1"
Get-ClarifyAdvice -Task "给 QQ 发消息"
```

Record one line when a decision point closes:

```powershell
Add-ClarifyRecord -Task "QQ 发消息给王金旭" -Domain gui-automation `
  -AskedCount 0 -Outcome wrong `
  -Assumptions @("send button at 1340,916") `
  -Notes "actual x was 1076 because the group sidebar shifted the layout"

Add-ClarifyRecord -Task "STM32 点灯工程" -Domain embedded `
  -AskedCount 3 -AnsweredCount 3 -Outcome helped `
  -Notes "board model, LED pin, allowed to flash - all three changed the plan"
```

Read the pattern:

```powershell
Get-ClarifyStats -SinceDays 90
```

Rules for using it:

- **Advisory**: high `Helped` in a domain raises your prior to ask; high `Wasted` lowers it.
  Neither is permission to skip the judgement in §2/§3.
- **Stale after 90 days** — re-learn instead of trusting.
- **Never cite it to a user as authority** ("上次你说了…"). It only shapes what you do next.
- **Contradiction wins for the present**: if today's request conflicts with a record, today wins,
  and you record the new outcome instead of arguing with the old one.
- Keep records short and factual: task, domain, count, assumptions, outcome, one line of why.
