# Cortex Agent Design Document (Phase 1)

_This document specifies how Redac's Cortex orchestrator (embedded inside OpenClaw) manages multi-agent research workflows, aligned with the product pillars of speed, trust, privacy, and provenance described in `redac.md`._

---

## 2.1 Agent Architecture

### 2.1.1 Query Reception Pipeline
1. **Client submission** → The Redac web app sends a `POST /api/research` request containing:
   - `query`: natural language instruction from the researcher
   - `scope`: corpus filters (dates, domains, methodologies)
   - `plan_hints`: optional structured instructions (e.g., "focus on EU regulation")
   - `token_context`: user tier, tokens remaining, priority flag
2. **Message bus enqueue** → An entry is written to the Task Queue (`tasks:research:<uuid>`). Cortex loads it, allocates a `job_id`, and emits a `task_started` event.
3. **Semantic framing** → Cortex runs a light-weight planning model (local llama.cpp for privacy) to classify:
   - Research intent (policy, technical, comparative, etc.)
   - Required citation strictness (systematic review vs quick scan)
   - Agent sequence template (Discovery → Screening → Theory → Output), optionally inserting auxiliary checks (Deduplication Agent) depending on the query.

### 2.1.2 Task Decomposition Logic
For a request like _"challenges of AI in finance from a policy perspective"_:
1. **Discovery planning**
   - Expand query into multiple sub-queries (e.g., "AI regulation banking", "algorithmic risk management policy finance").
   - Select source templates (Crossref/OpenAlex metadata, user private corpus, policy briefs inside private notes).
2. **Screening criteria synthesis**
   - Derive inclusion/exclusion rules: publication date range, domain keywords ("banking", "financial services"), methodology filters (policy papers, regulatory reports).
3. **Extraction agenda**
   - Define structured slots the Theory Agent must fill: `policy_area`, `challenge_description`, `evidence_snippet`, `source_ids`.
4. **Synthesis outline**
   - Output Agent receives a skeleton (intro, 3-5 challenges, implications, citations table) to ensure consistency with Redac's provenance logging.

### 2.1.3 Agent Routing
- **Discovery Agent**: Executes hybrid BM25 + vector search over the central metadata corpus and the user's encrypted corpus; returns ranked doc handles + metadata.
- **Screening Agent**: Batch-evaluates abstracts/full texts against criteria, labeling each handle as include/exclude + rationale.
- **Theory Agent**: Runs structured extraction on included docs, generating normalized policy challenge entities with citation pointers.
- **Output Agent**: Generates narrative + tables, enforcing citation anchors and preparing assets (PRISMA counts, gap analysis summary).

#### Agent Hierarchy (ASCII)
```
                      ┌────────────────────┐
                      │  Cortex Orchestrator│
                      └─────────┬──────────┘
                                │plan + route
        ┌───────────────────────┼────────────────────────┐
        │                       │                        │
┌───────▼───────┐      ┌────────▼────────┐      ┌─────────▼────────┐      ┌────────▼────────┐
│Discovery Agent│      │Screening Agent │      │  Theory Agent    │      │  Output Agent   │
│(search/sourcing)│    │(inclusion ctrl)│      │(theme extraction)│      │(synthesis + QC) │
└───────┬───────┘      └────────┬────────┘      └─────────┬────────┘      └────────┬────────┘
        │feeds handles          │filters handles         │annotates themes        │produces deliverables
```

---

## 2.2 Workflow Example

### Scenario: _"What are the policy challenges of AI deployment in banking?"_

1. **Planning**
   - Cortex classifies domain = "financial regulation", evidence depth = "policy brief".
   - Emits `plan_ready` event with sub-task list.
2. **Discovery Agent**
   - Runs four search templates (OpenAlex, Crossref, user corpus, grey literature API) producing ~120 doc handles.
   - Stores raw hits in the `job_id:discovery` bucket.
   - Emits `discovery_completed` event containing hit counts and token usage.
3. **Screening Agent**
   - Applies inclusion filters (post-2018, keywords {"Basel", "governance", "compliance"}).
   - Returns 34 included abstracts with rationales + PRISMA tally.
4. **Theory Agent**
   - Extracts policy challenges grouped by themes: compliance burden, model risk transparency, data privacy, supervisory alignment.
   - Each theme references source IDs and quotes.
5. **Output Agent**
   - Builds final answer: narrative paragraphs, bullet summary, table of challenges vs policy levers, citation map.
   - Triggers hallucination guard before sending to user.

### Sequence Diagram (ASCII)
```
User → Cortex: submit query
Cortex → Planner: classify & decompose
Planner → Cortex: task graph
Cortex → Discovery: run multi-source search
Discovery → Cortex: hit list + metadata
Cortex → Screening: batch evaluate abstracts
Screening → Cortex: include/exclude + rationales
Cortex → Theory: extract policy themes
Theory → Cortex: structured findings
Cortex → Output: synthesize narrative + tables
Output → Cortex: draft report + citation map
Cortex → QA Hook: hallucination guard & verification
QA Hook → Cortex: pass/fail + fixes
Cortex → User: progress events + final artifact links
```

### Pseudocode
```python
def process_research_query(job):
    emit("task_started", job)
    plan = planner.decompose(job.query, job.scope)
    emit("plan_ready", plan)

    hits = discovery_agent.search(plan.discovery_plan)
    emit("discovery_completed", summary(hits))

    screened = screening_agent.filter(hits, plan.screening_rules)
    emit("screening_completed", summary(screened))

    themes = theory_agent.extract(screened.included, plan.extraction_slots)
    emit("extraction_completed", summary(themes))

    draft = output_agent.compose(themes, plan.output_outline)
    qa_result = hallucination_guard.verify(draft, themes)

    if qa_result.passed:
        emit("completed", draft)
    else:
        emit("needs_review", qa_result.issues)
```

---

## 2.3 Progress Tracking

### Event Stream (WebSocket / SSE)
| Event Name             | Trigger                                           |
|------------------------|---------------------------------------------------|
| `task_started`         | Cortex picks up the job                           |
| `plan_ready`           | Planner finishes decomposition                    |
| `discovery_started`    | Discovery agent receives plan                     |
| `discovery_completed`  | Search hits consolidated                          |
| `screening_started`    | Screening begins                                  |
| `screening_completed`  | Inclusion/exclusion decisions finalized           |
| `extraction_started`   | Theory Agent begins structured extraction         |
| `extraction_completed` | Themes/entities ready                              |
| `synthesis_started`    | Output Agent composing narrative                  |
| `verification_started` | Hallucination guard running                        |
| `completed`            | Final assets stored & ready                       |
| `error`                | Unrecoverable failure                             |

### Event Payload Schema
```jsonc
{
  "event": "screening_completed",
  "job_id": "job_7c1f",
  "timestamp": "2026-03-17T00:26:02Z",
  "stage": "screening",
  "status": "completed",
  "metrics": {
    "processed_docs": 120,
    "included": 34,
    "excluded": 86,
    "token_usage": {
      "prompt": 3100,
      "completion": 2100
    }
  },
  "artifacts": {
    "prisma_counts": {
      "identified": 120,
      "screened": 120,
      "included": 34
    }
  }
}
```
- Events are emitted over a WebSocket channel keyed by `job_id`. REST clients can poll `/api/research/{job_id}/events` for the same feed.

---

## 2.4 Error Handling & Fallbacks

| Failure Type                    | Strategy                                                                 | User Notification                                      |
|---------------------------------|--------------------------------------------------------------------------|--------------------------------------------------------|
| API timeout / rate limit        | Automatic retry (exponential backoff up to 3 attempts). If still failing, switch to cached corpus snapshot. | `error` event with `retrying` flag before fallback.    |
| Discovery returns insufficient hits | Relax filters (expand date range, remove niche keywords).              | `discovery_completed` includes `coverage_warning`.     |
| Screening hallucination guard triggers (e.g., agent contradicts inclusion rules) | Re-run batch with deterministic smaller model (OpenAI gpt-4o-mini fallback). | `screening_completed` events include `consistency_fix`.|
| Theory agent extraction failure | Break batch into smaller chunks; if failure persists, degrade to template-based summary referencing raw quotes. | Emit `extraction_warning` before proceeding.           |
| Output QA failure               | Send `verification_failed` event, keep draft in “fix required” state, and run automatic citation repair (see §2.6). | User sees `needs_review` message with actionable text.|
| Catastrophic failure (planner crash, storage outage) | Abort job, refund tokens, persist crash log. | `error` event with `recoverable:false` + support ticket ID. |

Fallback models default to on-prem/local (llama.cpp / MLX) first to preserve privacy; only if policy allows will cloud models be used, and that path is logged in the methodology trace.

---

## 2.5 Token Tracking

1. **Per-Agent Metering**
   - Each agent runs behind a middleware that intercepts LiteLLM responses and records `{job_id, agent_name, prompt_tokens, completion_tokens, model}`.
   - Metrics are stored in `token_usage` table keyed by `job_id` + `subtask_id`.
2. **Real-Time Deduction**
   - After each sub-task, Cortex calls the billing service (`POST /api/tokens/deduct`) with:
     ```json
     {
       "user_id": "usr_123",
       "job_id": "job_7c1f",
       "agent": "screening",
       "tokens": 5200,
       "tier": "pro"
     }
     ```
   - The billing service enforces plan quotas (Free = 50 tokens, Pro = 500, Team = 2000 per member) and responds with remaining balance.
3. **UI Surfacing**
   - Progress events include `metrics.token_usage` so the dashboard can update the token meter in real time (as shown in §2.3 example payload).
4. **Audit Trail**
   - Once the job completes, Cortex posts a consolidated token ledger to the provenance log so the user can download usage receipts alongside methodology exports.

---

## 2.6 Hallucination Prevention

1. **Source-Bound Drafting**
   - Theory Agent outputs structured findings with `source_ids` referencing the discovery catalog; Output Agent is only allowed to cite facts present in these structures.
2. **Citation Graph Build**
   - Cortex constructs a mapping of `claim_id → {source_ids, snippets, confidence}`. Each paragraph in the draft is annotated with embedded tags (not visible to user) pointing to this map.
3. **Verification Step**
   - `hallucination_guard.verify(draft, themes)` performs:
     - **Trace Check**: Ensures every citation in the draft links to at least one verified `source_id`.
     - **Snippet Match**: Computes cosine similarity between cited text and stored snippet to confirm the claim is grounded.
     - **Completeness Scan**: Confirms PRISMA numbers match counts earlier in the pipeline.
4. **Failure Handling**
   - On missing citation: guard returns a list of `claim_ids` lacking sources → Output Agent rewrites or removes the claim.
   - On low similarity (<0.75): guard requests Theory Agent to re-extract evidence or flags the item for manual review.
   - Verification emits `verification_started` and either `completed` or `verification_failed` events (see §2.3).
5. **User Transparency**
   - Final deliverable includes a provenance appendix listing every source DOI/URL, the agent that touched it, and timestamps, satisfying Redac's radical transparency principle.

---

### Optional ASCII Flowchart
```
[User Query]
     |
     v
[Cortex Planner]-->[Plan Ready]
     |
     v
[Discovery Agent]-->[Hits]
     |
     v
[Screening Agent]-->[Included Docs]
     |
     v
[Theory Agent]-->[Policy Themes]
     |
     v
[Output Agent Draft]
     |
     v
[Hallucination Guard]
     |
   +---pass---> Deliver to user (completed)
   |
   +---fail---> Auto-repair + notify (needs_review)
```

---

**Status:** Ready for implementation & hand-off to engineering.
