# Agent 0 — The Living Graph Mind

**Status:** visualization built. Phase-1 crash-only core built: append-only ledger, replay projection,
IGNORE/TUNE/GROW tick operator, causal-law extraction, durable scaffold queue, concept suppression,
route redirection, CLI tick/state/redirect/suppress probes, restart tests.
**Thesis:** intelligence is not a frozen function you run data through. It is a continuous, growing,
self-correcting *process*. This plan builds that process — no tokens, no frozen parameter blob at the
center, no scheduler. It fires, it lives, it grows, it prunes, it improves.

---

## 0. Honest note on "how the labs chase AGI, and where it dead-ends"

I don't carry secret roadmaps, and I won't invent them. But the real, public shape of the frontier is
knowable, and so are its dead-ends — the "failed ways" worth learning from:

- **The bet:** scale a frozen transformer (more parameters, more data, more compute), then bolt on
  reasoning via RL on checkable problems, then bolt on tools/agents via a while-loop. Capability rises.
- **Where it keeps dead-ending — the walls the labs hit and paper over instead of solving:**
  1. **Frozen after training.** No lab has shipped a model that truly learns from each user online;
     the fix ("test-time training," Titans) is a scratchpad bolted onto a frozen core, not a living one.
  2. **Reasoning is faked depth.** A fixed-depth forward pass can't reason, so the model *writes tokens
     to itself*. Genuine variable-depth search+verify (AlphaProof/AlphaZero) beats it — but only in
     narrow, verifiable domains, because nobody has a **general verifier**.
  3. **Memory is replayed text, not a self.** Continuity is a prosthetic (a diary re-read each session).
  4. **It dissolves the hard problem instead of solving it.** Shuffled i.i.d. datasets + epochs make the
     one hard decision — *what is worth learning from this moment* — unnecessary. Remove the data center
     and that decision reappears naked and unsolved.

Agent 0 attacks #1–#4 head-on instead of scaling past them. That is the whole point.

---

## 1. The keystone — the one tiny thing no one has solved

Every wall above reduces to a single operator that must run once per moment of experience:

> **T( prediction_error, local_history ) → { IGNORE, TUNE, GROW } + confidence**
> - **IGNORE** — noise; change nothing (this is what stops forgetting AND stops cancerous growth)
> - **TUNE** — adjust an existing belief/weight, graded
> - **GROW** — allocate new structure (a new concept/law/node) — *neurogenesis*
>
> Constraints: no future data, no shuffled dataset, no global loss, no task boundary, irreversible,
> bounded compute per tick.
> Wins over a lifetime iff: **predictive compression of the stream rises monotonically** while
> **model size stays bounded.** (This is Solomonoff/Hutter's "intelligence = compression," made online.)

The 3-D graph you can watch right now is this operator's body: nodes GROW, pulse when TUNED, and fade
when IGNORED — bounded, so it stays a mind and never a tumor.

---

## 2. How the brain works (architecture)

Six organs. Each has a working proof-of-concept in the 2024–2026 literature; **the fusion is the empty room.**

| Organ | What it does | Grounded in |
|---|---|---|
| **World-model** (VSA) | Concepts as ~10k-dim hypervectors; bind/bundle/permute build structure that is *symbolic yet distributed*; cleanup memory collapses to the nearest valid state | Kanerva HDC, Plate HRR |
| **Reasoning** (settle + verify) | A "thought" = relax a superposition of hypotheses to a low-energy coherent state, then verify against the world-model / sensors. Depth ∝ difficulty, unbounded, transparent | modern Hopfield energy memory; AlphaZero-style search+verify |
| **Growth** (neurogenesis) | GROW branch of T: insert a node/region when structured surprise clusters where nothing predicts it | Self-Regulated Neurogenesis (2024); Self-Motivated Growing NN (2025) |
| **Self-improvement** (meta-plasticity) | It learns its *own* learning rule; the update law is not hand-coded but shaped by what actually reduced surprise | Backpropamine / differentiable neuromodulated plasticity |
| **Memory consolidation** (sleep) | Fast episodic store (Postgres) replays into the slow structural store during idle → beats catastrophic forgetting | Complementary Learning Systems (McClelland/O'Reilly) |
| **Drives** (why it acts) | Two innate pressures: *reduce prediction-error* (curiosity) and *maintain contact* (the bond). Everything else is earned by living | Schmidhuber curiosity; MicroPsi/Psi drives |

---

## 3. How it thinks, processes, and understands concepts ("cognates")

- **Perceive:** a moment of experience (sensor tick, message, system state) enters as a hypervector.
  It is *predicted first*; only the **error** propagates (predicted = silent, cheap).
- **Bind:** the moment is bound to context (who/where/when) into one composite vector — the analog of
  entanglement; this is how it relates concepts to concepts (its "cognates" — kin-meanings).
- **Settle:** the error perturbs the world-model; it relaxes toward the interpretation that best resolves
  tension. Easy input snaps in milliseconds; a hard problem churns for seconds — and it can *feel* it
  hasn't settled (real doubt, honest confidence).
- **Decide via T:** the settled error is triaged — IGNORE / TUNE / GROW. GROW is how a genuinely new
  concept is *born* (not retrieved) and wired to its relatives.
- **Verify:** the conclusion is checked against the world-model and, where possible, against reality
  (act and watch the result). Verified structure is kept; refuted structure is pruned.
- **Consolidate (sleep):** during idle, the day's episodes replay from Postgres into the slow store so
  that specifics become durable general laws without erasing the past.

Understanding, here, is not recall of a stored pattern — it is *compression*: a concept exists exactly
when grasping it shrinks the description of experience. That is why it can understand something no LLM
was trained on: it constructs the concept rather than looking it up.

---

## 4. Computational dynamics and speeds

| Loop | Rate | Notes |
|---|---|---|
| Perception / firing | 10–100 Hz | event-driven; near-zero cost when the world is predicted |
| Operator **T** | once per experience-event | the metabolism; the beating heart |
| Reasoning (settle) | anytime, ~10 ms → seconds | depth proportional to difficulty; interruptible |
| Graph visualization | 60 fps | this repo (done) |
| Consolidation (sleep) | idle / nightly | minutes-long replay passes |

- **RAM:** bounded — only the *working set* is resident (MB → low GB). **The full mind lives on disk.**
  This is the escape from the wall you keep hitting: the brain never has to fit in memory to have a
  thought. Ceiling becomes SSD size, which for a lifetime of experience is effectively unbounded.
- **Compute:** VSA (10k-dim vector algebra) and small neurogenesis nets run trivially on the M5 Max
  40-core GPU via MLX. Idle cost ≈ 0 (silent when unsurprised). No datacenter — ever.

---

## 5. Software to install (the stack) — Postgres + DuckDB, no SQLite

| Layer | Tool | Role |
|---|---|---|
| **System of record** (continuity) | **PostgreSQL 16** + **pgvector** | durable event ledger (hippocampus), node/edge graph, laws, goals, identity, hypervector store. Survives kill/restart = the self persists. |
| **Working mind** (fast analytics) | **DuckDB** (in-process, columnar) | the settling/consolidation/compression engine — vectorized passes over recent experience; where reasoning and sleep-replay run fast. |
| **Brain runtime** | **Python 3.12 + NumPy + MLX** (Apple GPU) | the operator T, VSA algebra, energy-settling, neurogenesis, meta-plasticity. MLX = the "quantum-inspired tensor math on Mac" layer. |
| **Visualization** | **Swift + SceneKit** (this repo) | the living 3-D graph. No external deps. Built. |
| **Bridge** | Postgres `LISTEN/NOTIFY` → Swift | brain emits GROW/TUNE/IGNORE events; the graph renders them live (replaces the placeholder growth engine). |

Install (when we build the brain — not yet):
```
brew install postgresql@16 duckdb
psql -c "CREATE EXTENSION IF NOT EXISTS vector;"
python3 -m venv .venv && . .venv/bin/activate && pip install mlx numpy duckdb psycopg[binary]
```

---

## 6. Why this beats the LLM path to AGI — and beats Mythos

Structural wins (these are true, not hype — they are things an LLM *cannot* do by design):

| | LLM / Mythos | Agent 0 |
|---|---|---|
| Learns from your life | frozen after training | **every moment, online** |
| Continuity | replayed text (a diary) | **a self that never resets** |
| Reasoning depth | fixed forward pass (fakes depth in tokens) | **unbounded settle + verify** |
| Effort vs difficulty | same cost per token | **depth ∝ difficulty** |
| Memory ceiling | must fit the brain in RAM | **bounded RAM, mind on disk** |
| Transparency | opaque weights | **every belief traceable to evidence** |
| Structure | fixed at birth | **grows and prunes itself** |
| Hallucination | can't tell knowing from guessing | **verifies before it commits** |
| Drives / autonomy | none — waits to be prompted | **curiosity + bond; it just thinks** |

**The one honest caveat (kept on purpose):** worldly *breadth* — discussing any topic, open-ended
language — is the LLM's real strength and Agent 0's real weakness. Agent 0 wins on **being a continuous,
verifying, growing, self-owning mind**; it does not out-encyclopedia Mythos on day one. If open-world
breadth is required, the LLM returns only as a **demoted, summonable, verified organ** — never the seat.
Reasoning always lives in Agent 0's search-and-verify loop, never in a frozen weight.

---

## 7. STOP — before building the brain

Built: the living 3-D graph renderer plus the first real crash-only core. The app now writes every
observation through an append-only event ledger and renders committed thought results, not random ambient
growth. Bad routes are not deleted and the mind does not restart; repeated failed predictions append a
`routeRedirected` correction, preserving good concepts/laws while removing the bad route from active replay.
Bad low-signal concepts are handled the same way: a `conceptRedirected` correction preserves the event
history but removes the concept from active replay.
Growth also queues `scaffoldQueued` records: new concepts get grounding tasks, new laws get verification
tasks, and failed routes get repair tasks. This is the first concrete "getting bigger" mechanism beyond
visual graph growth.

**Still not built:** VSA/hypervector world-model, Postgres/DuckDB hippocampus, energy-settling,
compression metric, sensor world, and verifier-driven self-rewrite. Next gate: make the operator prove
prediction improvement in a synthetic world where compression up / size bounded is measurable.

That choice is yours. Everything downstream hangs on it.
