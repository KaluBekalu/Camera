# Research — what to build this with

Landscape as of August 2026. Prices and latency figures are ballparks from vendor docs
and third-party benchmarks — re-check before you commit to anything, they move monthly.

---

## 1. The voice loop

This is the part that decides whether the product feels alive. Two fundamentally
different approaches:

### Cascade — STT → LLM → TTS

Separate models chained: transcribe speech, feed text to an LLM, speak the reply.

- **Pro:** you pick any LLM. You get the transcript for free (needed for session
  review). You can send images and structured data to the LLM. Every piece is
  swappable.
- **Con:** more moving parts, and latency stacks up across three hops.

### Speech-to-speech — one model, audio in, audio out

OpenAI Realtime, Gemini Live, and similar. Audio never becomes text in the middle.

- **Pro:** lowest latency, best prosody and turn-taking, hears *how* you said it.
  Measured end-to-end latency across providers currently spans roughly 0.8s to 3.0s.
- **Con:** you're locked to that provider's model for the actual thinking. That's the
  disqualifier here.

### → Decision: cascade

The tutor's job is to look at a system-design diagram and say *"you put the cache in
front of the wrong thing."* That is a reasoning-and-vision task, and it's the reason
you'd choose a particular model at all. A speech-to-speech model would make you accept
whatever reasoning ships inside the voice model.

Common guidance in the voice-agent community agrees: default to cascade, and reach for
speech-to-speech only when naturalness *is* the product. Here, insight is the product.

**Escape hatch:** the architecture keeps STT and TTS as swappable adapters, so a future
speech-to-speech mode for pure behavioral-interview practice (where naturalness matters
most and no diagram is involved) is a plug-in, not a rewrite.

---

## 2. Voice orchestration frameworks

You do not want to hand-roll WebSocket audio plumbing, barge-in, and turn-taking. That
is weeks of work and it's the part that's hard to get right.

| Framework | Language | Shape | Best when |
|---|---|---|---|
| **Pipecat** | Python | Pipeline of processors; audio and text flow through | Solo builder, local dev, want to swap providers freely |
| **LiveKit Agents** | Python / Node | Agent layer on top of LiveKit's WebRTC infra | You need real WebRTC transport, multiple users, or telephony |
| **Vapi / Retell** | Hosted | Managed voice-agent platform | You want it to just work and don't mind the walls |

### → Pick: Pipecat for v1

It originated at Daily, models the agent as a pipeline, has by far the widest set of
provider plugins (including an Anthropic LLM service), and handles the hard real-time
concerns — interruption, turn-taking, audio buffering — for you. It runs comfortably on
your laptop, which matters a lot when you're the only user.

**Switch to LiveKit Agents if:** you want this reachable from your phone, or over a
real network with proper WebRTC, or you eventually want more than one person in a
session. LiveKit's transport story is genuinely stronger; it also shipped native SIP and
phone numbers in 2025, so telephony no longer needs a Twilio bridge. The pipeline logic
ports over without much drama.

**Skip Vapi/Retell:** they're built for phone-call agents. You need deep custom
workspace context injected on every turn, which is exactly what hosted platforms make
awkward.

---

## 3. Speech-to-text

Streaming, low-latency, with good end-of-speech detection. That last property matters
more than raw word error rate for this use case — see the turn-detection problem in
[PLAN.md](./PLAN.md#the-hardest-ux-problem-silence-is-not-the-same-as-finished).

| Provider | Streaming latency (reported) | Notes |
|---|---|---|
| **Deepgram Nova-3 / Flux** | ~300ms partials; Flux is purpose-built for voice agents and posts the lowest end-of-speech detection latency measured in May 2026 | Best turn-detection story |
| **AssemblyAI Universal-3 Pro** | ~307ms P50, 8.14% WER in a 4M-call production benchmark | Better accuracy in that same benchmark than Nova-3's 516ms / 9.87% |
| **ElevenLabs Scribe v2 Realtime** | ~150ms first partial, 90+ languages | Fastest first-partial figure |

Benchmarks disagree loudly with each other depending on audio conditions — treat the
table as "these three are all viable," not as a ranking.

### → Pick: Deepgram (Flux if available on your plan)

End-of-speech detection is the thing that will make or break the feel, and that's what
Flux is explicitly built for. Keep the STT adapter thin so swapping to AssemblyAI is a
config change; run both against a recording of yourself thinking out loud before
committing.

---

## 4. Text-to-speech

Needs streaming output and, critically, **cancellable mid-utterance** — when you
interrupt the tutor, it has to stop talking immediately.

| Provider | Time-to-first-audio | Notes |
|---|---|---|
| **Cartesia Sonic 3.5** | ~75–90ms over WebSocket in vendor figures; one independent 7-day window measured 270ms median but a very tight 374ms p95 | Consistently cheapest per minute, very stable tail latency |
| **ElevenLabs Flash v2.5** | ~75ms claimed; ~208ms median measured in the same independent window, but 2,906ms p95 | Better voice quality, much worse tail |

That p95 gap is the interesting number. A tutor that occasionally takes three seconds to
start talking breaks the illusion far worse than one that always sounds slightly less
natural.

### → Pick: Cartesia

Predictability beats peak quality for conversational feel. Revisit if the voice quality
bothers you in practice.

---

## 5. The LLM

Anthropic has no realtime speech API, which is another reason the cascade decision is
already made. The models are reached through the normal Messages API.

Relevant capabilities for this project:

- **Vision** — send a PNG of the canvas. High-resolution support (2576px long edge)
  matters for dense diagrams.
- **Prompt caching** — the system prompt, rubric, and problem statement are identical
  across every turn in a session. Caching them is the single biggest latency and cost
  lever you have. Minimum cacheable prefix is 512 tokens on the newest models.
- **Structured outputs** — for the coach-notes object that drives the rubric sidebar.
- **Effort control** — run conversational turns cheap and fast, analytical passes deep.

Model split (see [PLAN.md](./PLAN.md#decision-4-two-models-not-one)):

| Role | Model | Why |
|---|---|---|
| Conversational turns | `claude-haiku-4-5` or `claude-sonnet-5` at low effort | Needs to be fast and terse, ~120 output tokens |
| Analytical passes | `claude-opus-5` | Needs to actually understand the diagram |

Start both on Sonnet and split only when you've measured that you need to.

---

## 6. Sketch canvas

For system design, the workspace is a whiteboard.

| Library | Shape | Notes |
|---|---|---|
| **Excalidraw** (`@excalidraw/excalidraw`) | React component | Hand-drawn look, the aesthetic you described. Imperative `excalidrawAPI`, scene import/export, `exportToBlob` / `exportToSvg` / `exportToCanvas` via `@excalidraw/utils` |
| **tldraw** | React SDK | Infinite canvas, WebGL rendering, multiplayer sync built in. Its "Make Real" demo is precisely the sketch-to-LLM-vision pipeline you'd be building |
| **Konva / Fabric.js** | Low-level canvas | Only if you want to build the whiteboard yourself. You don't |

### → Pick: Excalidraw

It matches the "sketching on paper" feel you described, the export utilities are exactly
what the vision pipeline needs, and — the underrated part — **the scene JSON is
structured data.** You get shape types, text labels, arrow bindings, and groupings as
plain objects. That means you can send the tutor a precise text digest of the diagram
alongside the image, instead of asking a vision model to squint at hand-drawn boxes.
This is the single highest-leverage detail in the whole design.

tldraw is the better pick if you later want real-time multiplayer or need the WebGL
performance on very large canvases. Its Make Real work is worth reading either way.

---

## 7. Code editor

For algorithm mode.

- **CodeMirror 6** — light, modular, excellent for embedding. Fine-grained change
  events, which is what you want for the "watch the student type" observer.
- **Monaco** — VS Code's editor. Heavier, better IntelliSense, more familiar.

### → Pick: CodeMirror 6

You need change observation and a small bundle far more than you need language servers.

**Execution** (later, optional): **Pyodide** to run Python in the browser with no
backend, or **Judge0** / **Piston** for multi-language server-side execution. Not needed
for v1 — an interviewer doesn't run your code either, they read it and ask about it.

---

## 8. Desktop wrapper and screen capture

You floated two options: give the app screen-reading permission, or give it its own
canvas.

| Approach | Verdict |
|---|---|
| **In-app canvas** | ✅ Start here. Structured scene data, no OS permissions, no privacy surface, and the tutor knows exactly what changed |
| **Screen capture** | Defer. `getDisplayMedia` works in a plain browser tab — you don't even need a desktop app for it. Add it when you want to practice in your real IDE |
| **Electron** | If you need a desktop app: mature screen-capture APIs (`desktopCapturer`), easy to build |
| **Tauri** | Smaller binaries, Rust core, but more friction for audio/screen work |

### → Decision: plain web app for v1

No wrapper at all. Everything you described — canvas, microphone, even screen capture —
works in a browser tab. Adding Electron buys you nothing at this stage and costs you
build complexity on day one.

---

## Summary of picks

| Layer | Pick | Fallback |
|---|---|---|
| Voice orchestration | Pipecat (Python) | LiveKit Agents |
| STT | Deepgram Flux | AssemblyAI Universal-3 |
| TTS | Cartesia Sonic | ElevenLabs Flash |
| LLM | Claude — Sonnet 5 fast path, Opus 5 analysis | — |
| Canvas | Excalidraw | tldraw |
| Editor | CodeMirror 6 | Monaco |
| Frontend | React + Vite + TypeScript | — |
| Shell | Browser tab | Electron, later, only if needed |

---

## Sources

- [Voice agent frameworks: Pipecat, LiveKit Agents, and friends — The Voice AI Wiki](https://soniox.com/wiki/voice-agent-frameworks)
- [Voice AI agents in production 2026 — Reactify Solutions](https://www.reactify-solutions.com/articles/voice-ai-agents-production-2026)
- [Vapi vs Pipecat vs LiveKit — Inworld](https://inworld.ai/resources/vapi-vs-pipecat-vs-livekit)
- [Build and Deploy LiveKit AI Voice Agents: The 2026 Playbook — Forasoft](https://www.forasoft.com/blog/article/livekit-ai-agents-guide)
- [Best STT Models for Voice AI Agents in 2026](https://www.autointerviewai.com/blog/best-stt-speech-to-text-models-voice-agents-2026)
- [STT API Benchmark 2026: Latency and Accuracy — Gradium](https://gradium.ai/content/stt-api-benchmark-2026-latency-accuracy)
- [AssemblyAI vs Deepgram — Gladia](https://www.gladia.io/blog/assemblyai-vs-deepgram)
- [ElevenLabs vs Cartesia: latency & WER independent benchmark — Openbenchmarks](https://openbenchmarks.com/text-to-speech-benchmark-by-coval/elevenlabs-vs-cartesia)
- [Cartesia vs ElevenLabs for Voice AI: Latency, Quality, and Cost in 2026](https://burki.dev/blog/41-cartesia-vs-elevenlabs-tts)
- [@excalidraw/excalidraw — npm](https://www.npmjs.com/package/@excalidraw/excalidraw)
- [excalidrawAPI — Excalidraw developer docs](https://docs.excalidraw.com/docs/@excalidraw/excalidraw/api/props/excalidraw-api)
- [Integration and Embedding Guide — Excalidraw](https://deepwiki.com/excalidraw/excalidraw/10-integration-and-embedding-guide)
- [tldraw: Infinite Canvas SDK for React](https://tldraw.dev/)
- [Make Real: tldraw's AI Adventure — Steve Ruiz](https://gitnation.com/contents/make-real-tldraws-ai-adventure)
