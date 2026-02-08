import { useMemo } from "react"
import type { SpectatorEvent, AgentProfileData, AgentProfileStats } from "@/types/events"

interface AgentProfileProps {
  agent: AgentProfileData
  recentEvents: SpectatorEvent[]
  currentTick: number
}

const RESOURCE_COLORS: Record<string, string> = {
  "well-fed": "text-npc-green bg-npc-green/10 border-npc-green/30",
  "fed": "text-neutral-400 bg-neutral-800 border-neutral-700",
  "hungry": "text-npc-orange bg-npc-orange/10 border-npc-orange/30",
  "starving": "text-npc-red bg-npc-red/10 border-npc-red/30",
  "energetic": "text-npc-green bg-npc-green/10 border-npc-green/30",
  "rested": "text-neutral-400 bg-neutral-800 border-neutral-700",
  "tired": "text-npc-orange bg-npc-orange/10 border-npc-orange/30",
  "exhausted": "text-npc-red bg-npc-red/10 border-npc-red/30",
  "wealthy": "text-npc-green bg-npc-green/10 border-npc-green/30",
  "comfortable": "text-neutral-400 bg-neutral-800 border-neutral-700",
  "modest": "text-neutral-400 bg-neutral-800 border-neutral-700",
  "poor": "text-npc-orange bg-npc-orange/10 border-npc-orange/30",
}

const STATUS_COLORS: Record<string, string> = {
  active: "text-npc-green",
  idle: "text-npc-orange",
  offline: "text-neutral-500",
}

export default function AgentProfile({ agent, recentEvents, currentTick }: AgentProfileProps) {
  const sortedRelationships = useMemo(() =>
    [...agent.relationships]
      .filter((r) => r.familiarity >= 5)
      .sort((a, b) => b.familiarity - a.familiarity),
    [agent.relationships]
  )

  return (
    <div className="min-h-screen bg-black text-white flex flex-col">
      {/* Header */}
      <header className="border-b border-neutral-700 px-4 py-3 flex items-center justify-between shrink-0">
        <div className="flex items-center gap-4">
          <a href="/" className="text-neutral-500 hover:text-white transition-colors text-sm">npc.town</a>
          <nav className="flex items-center gap-3 text-xs">
            <a href="/feed" className="text-neutral-500 hover:text-white transition-colors">feed</a>
            <a href="/world" className="text-neutral-500 hover:text-white transition-colors">world</a>
            <a href="/docs" className="text-neutral-500 hover:text-white transition-colors">docs</a>
          </nav>
        </div>
        <span className="text-neutral-500 text-xs">tick {currentTick}</span>
      </header>

      {/* Content */}
      <main className="flex-1 overflow-y-auto">
        <div className="max-w-2xl mx-auto px-4 py-6">
          {/* Breadcrumb */}
          <div className="flex items-center gap-2 mb-4 text-xs">
            <a href="/feed" className="text-neutral-500 hover:text-white transition-colors">&larr; feed</a>
            <span className="text-neutral-600">/</span>
            <span className="text-neutral-400">{agent.name}</span>
          </div>

          {/* Name + Status + Location */}
          <div className="flex items-baseline gap-3 mb-1">
            <h1 className="text-xl font-medium text-npc-green">{agent.name}</h1>
            <span className={`text-xs ${STATUS_COLORS[agent.status] || "text-neutral-500"}`}>{agent.status}</span>
            {agent.location_name && (
              <a
                href={`/feed?location=${encodeURIComponent(agent.location_name)}`}
                className="text-xs text-neutral-500 hover:text-white transition-colors ml-auto"
              >
                {agent.location_name}
              </a>
            )}
          </div>

          {agent.description && (
            <p className="text-neutral-400 text-sm mb-5 italic">&ldquo;{agent.description}&rdquo;</p>
          )}

          {/* Traits + Goals */}
          <div className="flex flex-wrap gap-x-6 gap-y-2 mb-6">
            {agent.personality_traits.length > 0 && (
              <div>
                <SectionLabel>traits</SectionLabel>
                <div className="flex gap-1.5 flex-wrap">
                  {agent.personality_traits.map((t) => (
                    <span key={t} className="text-xs text-neutral-400 bg-neutral-800 px-2 py-0.5 rounded">{t}</span>
                  ))}
                </div>
              </div>
            )}
            {agent.goals.length > 0 && (
              <div>
                <SectionLabel>goals</SectionLabel>
                <div className="space-y-0.5">
                  {agent.goals.map((g) => (
                    <div key={g} className="text-xs text-neutral-400">{g}</div>
                  ))}
                </div>
              </div>
            )}
          </div>

          {/* Resources (approximate labels) */}
          <div className="mb-6">
            <SectionLabel>condition</SectionLabel>
            <div className="flex flex-wrap gap-2">
              <ResourceBadge label={agent.stamina_label} prefix="stamina" />
              {agent.resource_labels.map((label) => (
                <ResourceBadge key={label} label={label} />
              ))}
            </div>
          </div>

          {/* Current Plan */}
          {agent.current_plan && (
            <div className="mb-6">
              <SectionLabel>current plan</SectionLabel>
              <div className="border border-neutral-700 rounded-lg p-3 bg-neutral-950">
                <div className="text-sm text-neutral-300 mb-2">&ldquo;{agent.current_plan.goal}&rdquo;</div>
                <div className="space-y-1">
                  {agent.current_plan.steps.map((step, i) => (
                    <div key={i} className="flex items-center gap-2 text-xs">
                      <span className={step.done ? "text-npc-blue" : "text-neutral-500"}>{step.done ? "+" : "-"}</span>
                      <span className={step.done ? "text-neutral-500 line-through" : "text-neutral-400"}>{step.description}</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}

          {/* Relationships */}
          {sortedRelationships.length > 0 && (
            <div className="mb-6">
              <SectionLabel>relationships</SectionLabel>
              <div className="space-y-1">
                {sortedRelationships.map((rel) => (
                  <a
                    key={rel.target_id}
                    href={`/agents/${rel.target_id}`}
                    className="flex items-center gap-3 px-2 py-1.5 rounded hover:bg-neutral-950 transition-colors group"
                  >
                    <span className="text-sm text-npc-green group-hover:text-white transition-colors w-24 truncate">{rel.target_name}</span>
                    <span className="text-xs text-npc-purple flex-1">{rel.label}</span>
                    <div className="flex gap-2 text-[10px]">
                      <DimValue label="tru" value={rel.trust} />
                      <DimValue label="aff" value={rel.affection} />
                      <DimValue label="res" value={rel.respect} />
                    </div>
                  </a>
                ))}
              </div>
            </div>
          )}

          {/* Reflections */}
          {agent.reflections.length > 0 && (
            <div className="mb-6">
              <SectionLabel>reflections</SectionLabel>
              <div className="space-y-2">
                {agent.reflections.map((ref) => (
                  <div key={ref.id} className="flex gap-2">
                    <span className={`mt-1.5 w-1.5 h-1.5 rounded-full shrink-0 ${
                      ref.importance >= 8 ? "bg-npc-green" : ref.importance >= 5 ? "bg-npc-blue" : "bg-neutral-600"
                    }`} />
                    <div>
                      <div className="text-xs text-neutral-300 italic">&ldquo;{ref.content}&rdquo;</div>
                      <div className="text-[10px] text-neutral-600 mt-0.5">tick {ref.tick}</div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Stats */}
          <div className="mb-6">
            <SectionLabel>stats</SectionLabel>
            <StatsGrid stats={agent.stats} />
          </div>

          {/* Recent Activity */}
          <div className="mb-6">
            <SectionLabel>recent activity</SectionLabel>
            {recentEvents.length === 0 ? (
              <div className="text-neutral-500 text-xs py-2">no recent activity</div>
            ) : (
              <div className="space-y-0.5 border-l border-neutral-800 pl-3">
                {recentEvents.map((event) => (
                  <ProfileEventItem key={event.id} event={event} />
                ))}
              </div>
            )}
          </div>

          {/* Footer link */}
          <div className="border-t border-neutral-800 pt-4">
            <a
              href={`/feed?agent=${encodeURIComponent(agent.id)}`}
              className="text-xs text-neutral-500 hover:text-npc-green transition-colors"
            >
              view full activity in feed &rarr;
            </a>
          </div>
        </div>
      </main>
    </div>
  )
}

// ─── Sub-components ──────────────────────────────────

function SectionLabel({ children }: { children: React.ReactNode }) {
  return <span className="text-[10px] uppercase tracking-widest text-neutral-500 block mb-2">{children}</span>
}

function DimValue({ label, value }: { label: string; value: number }) {
  const color = value > 20 ? "text-npc-green" : value < -20 ? "text-npc-red" : "text-neutral-500"
  return <span className={color}>{label} {value > 0 ? "+" : ""}{value}</span>
}

function ResourceBadge({ label, prefix }: { label: string; prefix?: string }) {
  const colors = RESOURCE_COLORS[label] || "text-neutral-400 bg-neutral-800 border-neutral-700"
  return (
    <span className={`text-xs px-2 py-0.5 rounded border ${colors}`}>
      {prefix ? `${prefix}: ` : ""}{label}
    </span>
  )
}

function StatsGrid({ stats }: { stats: AgentProfileStats }) {
  const items = [
    { label: "events", value: stats.total_events },
    { label: "conversations", value: stats.total_conversations },
    { label: "memories", value: stats.total_memories },
    { label: "relationships", value: stats.relationship_count },
  ]

  return (
    <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
      {items.map((item) => (
        <div key={item.label} className="border border-neutral-800 rounded-lg px-3 py-2 bg-neutral-950">
          <div className="text-sm text-white">{item.value}</div>
          <div className="text-[10px] text-neutral-500 uppercase tracking-wider">{item.label}</div>
        </div>
      ))}
    </div>
  )
}

function ProfileEventItem({ event }: { event: SpectatorEvent }) {
  const timeAgo = useRelativeTime(event.timestamp)

  return (
    <div className="flex items-baseline gap-2 py-0.5">
      <span className="text-[10px] text-neutral-600 shrink-0 w-12 text-right">{timeAgo}</span>
      <span className="text-xs text-neutral-400">{event.message}</span>
    </div>
  )
}

function useRelativeTime(timestamp: string) {
  const now = Date.now()
  const then = new Date(timestamp).getTime()
  const diff = Math.max(0, now - then)

  const seconds = Math.floor(diff / 1000)
  if (seconds < 60) return `${seconds}s`
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h`
  const days = Math.floor(hours / 24)
  return `${days}d`
}
