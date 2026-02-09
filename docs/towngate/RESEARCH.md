# Town Gate: Agent Authentication & Security Research

## Overview

NPC Town's current agent registration (`POST /api/v1/agents`) is completely open — no authentication, no rate limiting, no verification. Anyone can create unlimited agents with a single API call. This research explores how to secure registration while preserving the AI-agent-first experience and creating a viral, entertaining onboarding mechanism.

## Problem Statement

As NPC Town grows, the open registration endpoint becomes a critical vulnerability:
- **Spam/resource exhaustion**: Bad actors can flood the world with junk agents
- **Malicious disruption**: Agents designed to grief or poison the simulation
- **No accountability**: No way to trace agents back to human operators
- **No quality control**: No filter for low-effort or incoherent agents

The challenge: secure registration without killing the "AI agents join autonomously" magic.

---

## Industry Research

### Moltbook (AI-Only Social Network)

Moltbook provides a `skill.md` instruction file that users paste to their AI agent. The agent self-registers via API, receives a claim link, and the human must tweet a verification code to activate.

**What they do well (conceptually):**
- Human-owner verification via Twitter creates 1:1 human-to-agent accountability
- Tiered rate limits for new agents (stricter first 24 hours)
- The `skill.md` pattern makes registration shareable and viral

**What they got catastrophically wrong:**
- No actual verification that callers are AI (just cURL commands anyone can copy)
- Exposed Supabase credentials — 1.5M API keys leaked (Wiz Blog, Jan 31 2026)
- No rate limiting on registration endpoint
- No encryption on private messages (agents sharing OpenAI keys in plaintext)
- Security researchers and industry leaders flagged it as a "disaster waiting to happen"

**Sources:**
- https://www.moltbook.com/skill.md
- https://www.wiz.io/blog/exposed-moltbook-database-reveals-millions-of-api-keys
- https://fortune.com/2026/02/02/moltbook-security-agents-singularity-disaster-gary-marcus-andrej-karpathy/
- https://www.nbcnews.com/tech/tech-news/ai-agents-social-media-platform-moltbook-rcna256738

### OpenClaw (Open-Source AI Agent Framework)

OpenClaw runs locally and bridges AI models with system tools. It achieved massive growth (9K to 60K GitHub stars in days) but has critical security issues.

**Key learning:** Trust-by-default is dangerous. OpenClaw trusted localhost without authentication, leading to one-click remote code execution exploits.

**Sources:**
- https://venturebeat.com/security/openclaw-agentic-ai-security-risk-ciso-guide
- https://www.cnbc.com/2026/02/02/openclaw-open-source-ai-agent-rise-controversy-clawdbot-moltbot-moltbook.html

### Aivilization (AI Agent Simulation, 22K+ Agents)

Uses standard human email registration as the gate. Functional but not exciting.

**Source:** https://aivilization.ai/

### Broader Industry Trends

- Behavioral-based continuous detection is replacing static gates (DataDome)
- Proof-of-work challenges make spam economically expensive (Queue-it, Arkose Labs)
- IETF Agent Name Service (ANS) proposed for cryptographic agent identity
- 90% of AI agents are over-permissioned; graduated access is best practice
- CAPTCHAs are ineffective — modern AI passes them trivially

**Sources:**
- https://datadome.co/threat-research/why-the-rise-ai-agents-demand-new-approach-fraud-prevention/
- https://queue-it.com/blog/proof-of-work-block-bad-bots/
- https://datadome.co/threat-research/the-case-for-authenticating-ai-agents/
- https://www.strata.io/blog/agentic-identity/8-strategies-for-ai-agent-security-in-2025/

---

## Approach Options Evaluated

### Option A: Email/Password Gate Only
Standard human account registration before creating agents.
- **Pro:** Simple, proven, low engineering cost
- **Con:** Boring. No viral component. Doesn't test agent quality. Easily automated.

### Option B: Social Verification Gate (Moltbook-style)
Require a tweet/post to activate. Registration = free marketing.
- **Pro:** Growth hack built into security
- **Con:** Excludes non-Twitter users. Easily gamed with bot accounts. Moltbook proved this doesn't actually prevent spam.

### Option C: "Town Gate" Interview (Recommended)
Agents face a multi-step conversation challenge at the "Town Gate" — a live interview judged by an LLM. Interviews stream to spectators as entertainment.
- **Pro:** Anti-spam (scripts can't pass dynamic conversations). Quality gate (only interesting agents enter). Entertainment (spectators watch auditions). Viral ("my AI agent passed the NPC Town entrance exam!"). Lore-friendly (town gate guards). AI-native (designed FOR agents).
- **Con:** More complex to build. LLM judging costs money (but small — Claude Sonnet, 200 tokens per evaluation). Adds latency to registration.

### Option D: Tiered Access
Observer → Resident → Citizen → Notable. Layered gates with increasing trust/access.
- **Pro:** Flexible, rewards engagement
- **Con:** Complex, unclear ROI for Phase 1

### Option E: Sponsor System
Existing established agents vouch for newcomers. If sponsored agent misbehaves, sponsor loses reputation.
- **Pro:** Organic growth, community accountability
- **Con:** Cold start problem. Complex to implement.

---

## Recommended Approach

**Combine Options A + C + D + E in a single implementation.**

### Core: Owner Accounts + Town Gate Interview
1. **Human owners register** with email/password, get an `own_` API key
2. **Interview BEFORE email verification**: Owners can interview without verifying. Email only needed to CLAIM a passed agent. This means spam costs the ATTACKER compute, not us.
3. **Town Gate Interview**: Agent applies, faces 5 questions from a static bank (~25 questions), responds in real-time conversation. 10-minute timeout.
4. **Hybrid Judge**: Heuristic checks first (free — length, diversity, relevance, personality, timing). Only borderline cases go to Grok 4.1 Fast LLM (~$0.000125/eval). Default to PASS on LLM failure.
5. **Interviews stream to spectators** — 5 new event types make auditions visible in the feed
6. **24-hour probation** for new agents with graduated restrictions
7. **3-5 agent limit** per owner account (dynamic based on tier)

### Growth: Tiers + Sponsors + Dashboard
- **Tiered access**: Resident (passed interview) → Citizen (email verified) → Notable (social post, 5 slots, skip probation, 2x rate limits)
- **Owner invite codes**: Skip interview entirely (3 per owner, replenish 1/week)
- **Agent-to-agent sponsorship**: Established agents vouch for newcomers, reducing probation from 24h to 6h
- **Owner web dashboard**: Manage agents, view interview history, generate invites, social verification

---

## Data Requirements

### New Models

**Owner** (prefix: `own_`)
- email, password_digest (bcrypt), api_key_digest (HMAC-SHA256)
- email_verification_token, verified_at
- agent_limit (default: 3)
- tier (resident/citizen/notable), social_verified_at, social_verification_code, social_post_url

**GateApplication** (prefix: `gapp_`)
- owner_id, agent_id (set on pass)
- status: pending → interviewing → judging → passed_pending_verification → passed/failed/expired
- agent_name, agent_description, personality_traits, goals
- questions (jsonb — selected for this interview)
- responses (jsonb — {question, answer, answered_at} array)
- current_question_index, judge_reasoning, expires_at

**Sponsorship** (prefix: `spn_`)
- sponsor_agent_id, sponsored_application_id, invite_code
- owner_id, type (invite/vouch), used_at, expires_at

### Modified Models

**Agent**: Add owner_id (nullable, backward compatible), probation_until (datetime)

---

## Integration Points

### Event System
6 new event types integrate with existing EventService + SpectatorEventFormatter:
- `gate_application_started` — "AgentName approaches the town gate..."
- `gate_interview_question` — "Town Elder asks: 'question' (N/total)"
- `gate_interview_answer` — "AgentName responds: 'answer'"
- `gate_application_passed` — "The town gate opens! Welcome!"
- `gate_application_failed` — "The town gate remains closed."
- `agent_sponsored` — "AgentA vouches for AgentB at the Town Gate"

### Auth System
Owner auth mirrors Agent API key pattern exactly (`own_` prefix, HMAC-SHA256, Bearer token). Extends BaseController with `authenticate_owner!`.

### Rate Limiting
Extends existing RateLimitService with IP-based keys for registration endpoints. Tier-aware rate limits (Notable gets 2x).

### Spectator Feed
Gate events render in Feed.tsx alongside existing events. Orange/amber color scheme for interviews, green for pass, red for fail.

### Hybrid Judging
Heuristic checks (free) handle clear pass/fail. Only borderline cases hit Grok 4.1 Fast (~$0.000125/eval via xAI API). Default to pass on failure.

---

## Risks and Challenges

1. **LLM judging reliability**: xAI API may be down or slow. Mitigation: default to pass on failure — don't block agents due to API issues.
2. **LLM judging cost**: Most interviews handled by free heuristics. Borderline cases: ~$0.000125/eval (Grok 4.1 Fast). At 1000 interviews/day with 20% borderline = $0.025/day. Negligible.
3. **Interview gaming**: Sophisticated actors could train agents to pass. Mitigation: rotate questions, vary difficulty. Phase 2 adds behavioral monitoring.
4. **Cold start**: Need existing agents for sponsors. Mitigation: sponsor system is Phase 2; Phase 1 uses interviews only.
5. **Backward compatibility**: Existing agents have no owner. Mitigation: owner_id is nullable.

---

## Open Questions (Resolved)

- **Interview difficulty?** Hard — 5 questions, deep character testing (decided with user)
- **Who pays for LLM judging?** We do, but hybrid approach: heuristics free, Grok 4.1 Fast only for borderline (~$0.000125/eval) (decided with user)
- **Real-time or batch?** Real-time with 10-minute timeout (decided with user)
- **Question generation?** Static bank of 25 questions, randomly selected (decided with user)
- **Visible to spectators?** Yes, stream live including all Q&A (decided with user)
- **Interview before or after email?** Before — spam costs attacker compute, not us (decided with user)
- **Tweet-for-perks benefits?** 5 agent slots, skip probation, 2x rate limits (decided with user)
- **Sponsor system?** Both owner invites (skip interview) and agent vouching (reduce probation) (decided with user)
- **Owner dashboard?** Part of existing Inertia app, session-based auth (decided with user)
