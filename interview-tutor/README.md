# Interview Tutor — voice-driven practice partner

> **Note:** this directory has nothing to do with the macOS Camera app in the rest of
> this repository. It lives on the `claude/interview-prep-ai-tutor-4nhkyc` branch as a
> scratch home for planning a separate project, and should be moved to its own repo
> before any real code lands.

## The idea

Replicate the experience of practicing with a human tutor: you talk, you sketch or you
write code, and you get instant conversational feedback — *"you missed the cache
invalidation there"*, *"I like that, why did you pick a queue?"*, *"what part are you
stuck on?"* — instead of typing into a chat box and reading paragraphs back.

Three practice modes:

| Mode | Workspace | What the tutor does |
|---|---|---|
| **Algorithms** | Code editor | Watches you code, probes your reasoning, nudges when stuck, never hands you the answer |
| **System design** | Sketch canvas | Watches the diagram grow, challenges components, asks the follow-ups an interviewer would |
| **Behavioral** *(later)* | Transcript only | Asks, listens, scores against a rubric |

## Documents

- **[RESEARCH.md](./RESEARCH.md)** — the landscape: voice frameworks, STT/TTS, canvas
  libraries, editors, desktop wrappers. Tradeoffs and picks, with the reasoning.
- **[PLAN.md](./PLAN.md)** — the architecture, the five design decisions that matter,
  latency and cost budgets, a phased build order, and the open questions.

## The short version

Build it as a **web app plus a Python voice agent**. No desktop wrapper, no screen
capture at v1 — an in-app canvas gives structured data (labels, arrows, groupings) that
beats screenshotting pixels, and skips OS permissions entirely.

The voice loop is a **cascade** (speech-to-text → Claude → text-to-speech), not an
end-to-end speech-to-speech model, because the tutor's whole value is reasoning about
your diagram and your code — and that reasoning is what you're choosing the model for.

Two models, not one: a **fast conversational model** for the back-and-forth, and a
**slower analytical pass** that runs in the background whenever your workspace changes
meaningfully and writes structured "coach notes" the fast model reads. That split is
what makes the tutor feel both snappy and actually insightful.

Build order starts with the riskiest part: **a voice loop you can interrupt.** Nothing
else matters if that doesn't feel right.
