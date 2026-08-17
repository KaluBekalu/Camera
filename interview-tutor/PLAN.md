# Plan — architecture and build order

Companion to [RESEARCH.md](./RESEARCH.md), which covers *which libraries*. This covers
*how the thing works* and *what to build first*.

---

## Locked decisions

| Question | Decision | Consequence |
|---|---|---|
| First mode | **Algorithms** | Phase 1 is the code editor. System design inherits the loop |
| Deployment | **Laptop only** | Pipecat, run locally. No WebRTC transport layer needed |
| Problems | **One simple built-in to start**, bring-your-own later | Needs a reference solution + rubric for that one problem |
| Tutor style | **Interjects proactively** | Adds a third observation trigger — see Decision 3 |

---

## The five decisions that matter

Everything else is implementation detail. These are the choices that determine whether
this feels like a tutor or like a chatbot with a microphone bolted on.

### Decision 1: cascade, not speech-to-speech

Covered in [RESEARCH.md §1](./RESEARCH.md#1-the-voice-loop). Short version: the tutor's
value is reasoning about your diagram, so the reasoning model is the thing you're
choosing, and a speech-to-speech model would make that choice for you.

### Decision 2: own the canvas, don't watch the screen

You raised both options. The canvas wins, and not just for privacy.

When you draw a box labelled "Redis" and an arrow from it to "API Gateway", Excalidraw's
scene JSON knows *exactly that*: an ellipse, its text label, an arrow with a bound start
and end element. A screenshot makes a vision model infer it from hand-drawn strokes.

So the workspace payload sent to the tutor is **both**:

1. A **text digest** derived from the scene JSON — precise, cheap, unambiguous:
   ```
   Components: [Client] [CDN] [API Gateway] [Auth Service] [Postgres (primary)] [Redis]
   Edges: Client→CDN, Client→API Gateway, API Gateway→Auth Service,
          API Gateway→Postgres, API Gateway→Redis
   Unlabeled: 1 rectangle near (840, 220)
   Free text: "shard by user_id?"
   ```
2. A **PNG snapshot** via `exportToBlob` — carries layout, grouping, spatial intent, and
   the messy stuff the digest can't express.

The digest also gives you a cheap change-detection primitive: diff two digests and you
know whether anything meaningful happened, without paying for a vision call.

Screen capture stays on the roadmap for "practice in my real IDE" later. It's a
`getDisplayMedia` call in the same browser tab — no desktop app needed.

### Decision 3: event-driven observation, not a polling loop

The naive version streams frames to the model continuously. That is expensive, slow, and
produces a tutor that interrupts constantly.

Instead, the tutor looks at your workspace on **exactly three triggers**:

- **You paused speaking** and the turn detector thinks you're done.
- **Your workspace changed meaningfully** — digest diff exceeds a threshold — and
  you've been quiet for N seconds.
- **The interjection gate fires** — the slow path spotted something urgent enough to
  speak up unprompted. See below.

Between those, nothing is sent. This is the difference between a $3/hour session and a
$40/hour one.

### The interjection gate

A tutor that interjects is the whole point — but an interjecting tutor with no brakes is
unbearable. Unprompted speech needs to clear every one of these:

1. **The slow path marked it urgent.** Coach notes carry an `urgency` field; only
   `high` is allowed to interrupt. A missing edge case can wait for the next pause; a
   fundamental misconception about what the code does cannot.
2. **You're not mid-flow.** No interjecting while you're actively typing or speaking.
   Requires a short quiet window on both the mic and the editor.
3. **Rate limit.** At most one unprompted interjection per N minutes, regardless of how
   much the tutor has to say. Ship with N high (two or three minutes) and tune down.
4. **Confidence is high.** The slow path already emits a confidence field. A tutor that
   interrupts to say something wrong is worse than one that stays quiet.

Build this as a single gate function with all four checks in one place, so tuning it is
editing one file rather than hunting through the pipeline. Expect to spend real time on
these thresholds — this is the knob that decides whether the tutor feels like a mentor
or a backseat driver.

### Decision 4: two models, not one

A single model can be fast or thoughtful, not both. Split the work:

```
┌─ FAST PATH (every turn, ~120 output tokens, low effort) ─────────────┐
│  Hears you. Reads the coach notes. Responds conversationally.        │
│  "Mm — why a queue there rather than a direct call?"                 │
└──────────────────────────────────────────────────────────────────────┘
                              ▲ reads
                              │
┌─ SLOW PATH (on meaningful workspace change, async, high effort) ─────┐
│  Studies the digest + snapshot + transcript so far.                  │
│  Emits a structured coach-notes object.                              │
└──────────────────────────────────────────────────────────────────────┘
```

The slow path emits **structured output**, not prose:

```jsonc
{
  "covered":       ["load balancing", "read replicas"],
  "missing":       ["cache invalidation", "failure modes for the queue"],
  "misconceptions":[{ "claim": "Redis gives us durability here",
                      "why_wrong": "no persistence configured; a restart loses the queue" }],
  "suggested_probe": "Ask what happens to in-flight jobs if Redis restarts.",
  "confidence": "high",
  "urgency": "high"   // gates unprompted interjection — see Decision 3
}
```

That object does triple duty: it steers the fast model's next question, it renders as a
live rubric sidebar the student can see, and it accumulates into the post-session
report. This is what turns the thing from a voice chatbot into a practice tool.

Start with both paths on the same model. Split only once you've measured that you need
to — premature splitting will cost you a week.

### Decision 5: prompt caching is not an optimization, it's the architecture

The system prompt, the rubric, the problem statement, and the mode instructions are
byte-identical across every turn of a session. Cache them and every turn after the first
reads them at a fraction of the cost and latency.

This constrains how you build the prompt: **stable content first, volatile content
last.** No timestamps, no session IDs, no turn counters interpolated into the system
prompt — those sit at the front of the prefix and invalidate everything behind them.
Dynamic context (current workspace digest, latest coach notes) goes at the *end*, in the
message array.

Get this wrong and you'll pay full price on every single turn and wonder why it's slow.

---

## The loop

```
                    ┌──────────────────────────────────────┐
   🎙  mic ────────▶│  VAD + semantic turn detection        │
                    └───────────────┬──────────────────────┘
                                    ▼
                    ┌──────────────────────────────────────┐
                    │  Streaming STT                        │
                    └───────────────┬──────────────────────┘
                                    ▼
   canvas ──┐       ┌──────────────────────────────────────┐
   editor ──┼──────▶│  Context assembler                    │
            │       │  cached prefix + digest + coach notes │
   coach ───┘       └───────────────┬──────────────────────┘
   notes                            ▼
                    ┌──────────────────────────────────────┐
                    │  Claude — fast path, streaming        │
                    └───────────────┬──────────────────────┘
                                    ▼
                    ┌──────────────────────────────────────┐
                    │  Streaming TTS  ◀── cancel on barge-in│
                    └───────────────┬──────────────────────┘
                                    ▼
                                  🔊 speakers

   (in parallel, on workspace change: slow path → coach notes)
```

---

## Latency budget

Target: **under 800ms** from you finishing a sentence to the tutor starting to talk.
Above roughly a second, the illusion of conversation breaks.

| Stage | Budget | Notes |
|---|---|---|
| End-of-speech detection | 150–300ms | **Dominates.** Use semantic turn detection, not raw silence |
| STT finalization | 100–300ms | Overlaps with the above if you use streaming partials |
| Claude first token | 300–600ms | Prompt caching is the lever; low effort, small `max_tokens` |
| TTS first audio | 75–250ms | Cartesia's tight p95 matters here |

Techniques that actually buy you time:

- **Cache the prefix.** Biggest single win.
- **Start TTS at the first sentence boundary**, not the end of the response.
- **Cap conversational `max_tokens` around 120.** A tutor's turn is a sentence or two.
  This is a latency lever *and* a quality lever — see the over-talking risk below.
- **Speculative context assembly:** build the next request's payload while the student
  is still talking, so the model call fires the instant the turn ends.

---

## The hardest UX problem: silence is not the same as finished

This is the thing that will take the most iteration, so plan for it.

When you're working through a hard problem, you go quiet. You stare at the diagram. You
mutter. You start a sentence, stop, restart. A naive voice-activity detector reads every
one of those pauses as "your turn is over" and the tutor talks over your thinking — which
is exactly the opposite of what a good tutor does.

Mitigations, roughly in order of how much they help:

1. **Semantic turn detection** rather than pure silence thresholds — models that judge
   whether an utterance is *complete*, not just whether audio stopped. This is why
   Deepgram Flux is the STT pick.
2. **Mode-dependent patience.** In algorithm mode while code is actively being typed,
   the silence threshold should be much longer. Typing is a signal that you're still
   working.
3. **Push-to-talk as an escape hatch.** Always available, on a hotkey. When the
   automatic detection frustrates you, you'll want it, and it costs an afternoon to
   build.
4. **A visible "thinking" state.** Let the student explicitly signal *"I'm working, hold
   on"* — a button, or a spoken phrase the tutor recognizes.

And the inverse: **barge-in must be instant.** When you start talking over the tutor, TTS
stops immediately and the partial utterance is discarded from context. A tutor you can't
interrupt is a lecturer.

---

## Cost

Very rough, for one hour of practice. Verify against current pricing before designing
around these.

| Component | Estimate |
|---|---|
| STT (continuous, 60 min) | ~$0.50 |
| TTS (tutor speaks maybe 20 min) | ~$0.50–1.00 |
| LLM fast path (~60 turns, cached prefix) | ~$0.50–2.00 |
| LLM slow path (~15 analytical passes with vision) | ~$1.00–3.00 |
| **Total** | **~$3–6 per hour** |

The two numbers that can blow up: sending vision on every turn instead of on meaningful
change, and failing to cache the prefix. Both are Decision 3 and Decision 5. Get those
right and the cost is fine.

---

## Build order

Each phase should be independently usable. The order is deliberately
riskiest-thing-first.

### Phase 0 — a voice you can interrupt *(the risky part)*

No canvas. No editor. No modes. Just: talk to Claude, hear it back, cut it off
mid-sentence and have it stop cleanly.

- Pipecat pipeline: Deepgram → Claude → Cartesia
- Barge-in working
- A latency HUD in the corner showing each stage's timing

**Done when:** you can have a five-minute conversation about anything and it doesn't feel
like walkie-talkie. If this phase doesn't feel right, nothing built on top of it will.

### Phase 1 — algorithm mode

- React + Vite frontend, CodeMirror 6 editor
- **One** built-in problem, with a reference solution and a rubric of the things a good
  answer covers. One is enough to tune the whole loop; a bank is Phase 3 work
- Code state sent on pause; tutor sees what you've written
- Slow path emitting coach notes against that rubric
- The interjection gate, with thresholds set conservatively
- Socratic system prompt (draft below)
- Push-to-talk hotkey

**Done when:** you can work the problem out loud, get useful nudges instead of the
answer, and the tutor interrupts you *only* when you'd want it to.

### Phase 2 — system design mode

- Excalidraw embedded
- Scene-JSON → text digest extractor (the important piece)
- `exportToBlob` snapshot on meaningful change
- Slow path emitting structured coach notes
- Live rubric sidebar rendering those notes

**Done when:** you can sketch a URL shortener, explain it aloud, and get asked the
questions a real interviewer would ask.

### Phase 3 — session review

- Full transcript with timestamps
- Coach notes accumulated across the session → post-session report
- Canvas/code snapshots at key moments
- "Here's what you consistently miss" across sessions

**Done when:** the report tells you something you didn't already know about yourself.

### Phase 4 — optional extensions

- Screen capture mode for practicing in your real IDE (`getDisplayMedia`)
- Code execution (Pyodide in-browser, or Judge0 server-side)
- Interviewer personas — friendly, adversarial, silent
- Spaced repetition: resurface the topics your reports say you're weak on
- Behavioral mode, possibly using a speech-to-speech model since naturalness dominates
  there and there's no diagram to reason about

---

## A starter system prompt

The tutor's default failure mode is talking too much and answering its own questions.
Prompt hard against both. Something like:

```
You are a technical interview coach sitting next to the candidate. You can see their
workspace and hear them think out loud.

How you talk:
- One or two sentences. This is a conversation, not a lecture.
- Ask more than you tell. When they're stuck, ask what specifically is blocking them
  before offering anything.
- Never give the answer. Give the smallest nudge that unblocks them.
- React to what they actually did, quoting it back: "you've got the cache in front of
  the gateway — what happens on a write?"
- Silence is fine. If they're working, let them work.

When they claim something, probe it. When they get something right, say so briefly and
move on — don't dwell.
```

Iterate on this more than on anything else. It's the highest-leverage file in the
project, and it's a text file.

---

## Known risks

| Risk | Mitigation |
|---|---|
| Turn detection interrupts your thinking | Semantic turn detection, mode-dependent patience, push-to-talk fallback |
| Tutor over-talks and lectures | Hard `max_tokens` cap around 120, explicit brevity in the prompt |
| Vision misreads hand-drawn sketches | The scene-JSON digest carries the precise structure; the image is supporting evidence |
| Cost runs away | Event-driven observation, prompt caching, vision only on meaningful change |
| Latency creeps past a second | Latency HUD from Phase 0 so regressions are visible immediately |
| Scope sprawl across three modes | Ship algorithm mode end-to-end before starting system design mode |

---

## Open questions

The four that shaped the code are settled — see [Locked decisions](#locked-decisions).
What's left is tuning, answerable only by using the thing:

1. **Interjection thresholds.** How urgent is urgent enough, how long a quiet window, how
   hard a rate limit. Ship conservative, loosen by feel.
2. **How long a "thinking pause" is normal for you.** Mode-dependent, and probably
   longer than any default. Measure it against a recording of yourself before tuning.
3. **Whether the fast and slow paths need different models.** Start both on the same one
   and split only when measurement says so.
4. **Whether coach notes should be visible during the session** or only in the report.
   Live is more useful; live may also be distracting mid-problem. Easy to toggle.
