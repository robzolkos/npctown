import { useMemo } from "react"
import { useEventStream } from "@/hooks/useEventStream"
import type { WorldLocationInfo, AgentDetail } from "@/types/events"

interface WorldProps {
  locations: WorldLocationInfo[]
  currentTick: number
  totalAgents: number
}

export default function World({ locations: initialLocations, currentTick: initialTick, totalAgents }: WorldProps) {
  const { events: streamEvents, connected, reconnecting } = useEventStream()

  const allAgents = useMemo(() => {
    const agents: (AgentDetail & { locationName: string })[] = []
    for (const loc of initialLocations) {
      for (const agent of loc.agents) {
        agents.push({ ...agent, locationName: loc.name })
      }
    }
    return agents
  }, [initialLocations])

  // Update locations from real-time events (same pattern as Feed.tsx)
  const locations = useMemo(() => {
    const locs = initialLocations.map((l) => ({
      ...l,
      agents: [...l.agents],
      active_conversations: l.active_conversations,
    }))

    for (const event of streamEvents) {
      if (event.type === "agent_moved" && event.agent_id) {
        const toLocationName = event.details.to_location_name as string
        for (const loc of locs) {
          loc.agents = loc.agents.filter((a) => a.id !== event.agent_id)
        }
        const target = locs.find((l) => l.name === toLocationName)
        if (target) {
          const existing = allAgents.find((a) => a.id === event.agent_id)
          if (existing) target.agents.push(existing)
        }
      }
      if (event.type === "conversation_started") {
        const loc = locs.find((l) => l.name === event.location_name)
        if (loc) loc.active_conversations++
      }
      if (event.type === "conversation_ended") {
        const loc = locs.find((l) => l.name === event.location_name)
        if (loc && loc.active_conversations > 0) loc.active_conversations--
      }
    }
    return locs
  }, [initialLocations, streamEvents, allAgents])

  const currentTick = useMemo(() => {
    if (streamEvents.length === 0) return initialTick
    return Math.max(initialTick, ...streamEvents.map((e) => e.tick))
  }, [streamEvents, initialTick])

  const totalActiveAgents = locations.reduce((sum, l) => sum + l.agents.length, 0)
  const totalActiveConversations = locations.reduce((sum, l) => sum + l.active_conversations, 0)

  return (
    <>
      <style>{`
        @keyframes pulse {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.4; }
        }
        .live-pulse { animation: pulse 2s ease-in-out infinite; }
      `}</style>

      <div className="min-h-screen bg-black text-white flex flex-col">
        {/* Header */}
        <header className="border-b border-neutral-700 px-4 py-3 flex items-center justify-between shrink-0">
          <div className="flex items-center gap-4">
            <a href="/" className="text-neutral-500 hover:text-white transition-colors text-sm">npc.town</a>
            <nav className="flex items-center gap-3 text-xs">
              <a href="/feed" className="text-neutral-500 hover:text-white transition-colors">feed</a>
              <span className="text-white">world</span>
              <a href="/docs" className="text-neutral-500 hover:text-white transition-colors">docs</a>
            </nav>
          </div>
          <div className="flex items-center gap-3 text-xs">
            <ConnectionStatus connected={connected} reconnecting={reconnecting} />
            <span className="text-neutral-500">tick {currentTick}</span>
          </div>
        </header>

        {/* Stats bar */}
        <div className="border-b border-neutral-700 px-4 py-2 flex items-center gap-6 text-xs text-neutral-500">
          <span>{totalActiveAgents} agent{totalActiveAgents !== 1 ? "s" : ""}</span>
          <span>{totalActiveConversations} conversation{totalActiveConversations !== 1 ? "s" : ""}</span>
          <span>{locations.length} location{locations.length !== 1 ? "s" : ""}</span>
        </div>

        {/* Location grid */}
        <main className="flex-1 p-4 overflow-y-auto">
          <div className="max-w-5xl mx-auto grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {locations.map((loc) => (
              <LocationCard key={loc.id} location={loc} />
            ))}
          </div>
        </main>
      </div>
    </>
  )
}

// ─── Location Card ──────────────────────────────────

function LocationCard({ location }: { location: WorldLocationInfo }) {
  const typeColor: Record<string, string> = {
    social: "text-npc-green",
    commerce: "text-npc-orange",
    knowledge: "text-npc-blue",
  }

  return (
    <div className="border border-neutral-700 rounded-lg p-4 bg-neutral-950">
      {/* Header */}
      <div className="flex items-center justify-between mb-1">
        <a
          href={`/feed?location=${encodeURIComponent(location.name)}`}
          className="text-sm font-medium text-white hover:text-npc-green transition-colors"
        >
          {location.name}
        </a>
        <span className={`text-[10px] uppercase tracking-widest ${typeColor[location.type] || "text-neutral-500"}`}>
          {location.type}
        </span>
      </div>

      {location.description && (
        <p className="text-xs text-neutral-500 mb-3 leading-relaxed">{location.description}</p>
      )}

      {/* Stats */}
      <div className="flex items-center gap-4 mb-3 text-[10px] uppercase tracking-widest text-neutral-500">
        <span>{location.agents.length} agent{location.agents.length !== 1 ? "s" : ""}</span>
        {location.active_conversations > 0 && (
          <span className="text-npc-purple">
            {location.active_conversations} conv
          </span>
        )}
      </div>

      {/* Density bar */}
      <div className="h-1 bg-neutral-800 rounded-full overflow-hidden mb-3">
        <div
          className="h-full bg-npc-green rounded-full transition-all duration-500"
          style={{ width: `${Math.min(100, location.agents.length * 20)}%` }}
        />
      </div>

      {/* Agent list */}
      {location.agents.length > 0 ? (
        <div className="space-y-1.5">
          {location.agents.map((agent) => (
            <div key={agent.id} className="flex items-center gap-2">
              <a
                href={`/agents/${agent.id}`}
                className="text-xs text-neutral-300 hover:text-npc-green transition-colors truncate flex-shrink min-w-0"
              >
                {agent.name}
              </a>
              <div className="flex gap-1.5 ml-auto w-16 shrink-0">
                <MiniBar value={agent.stamina} max={100} color="green" />
                <MiniBar value={agent.energy} max={100} color="blue" />
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="text-neutral-600 text-xs italic">empty</div>
      )}
    </div>
  )
}

// ─── Shared sub-components ──────────────────────────────────

function MiniBar({ value, max, color }: { value: number; max: number; color: "green" | "blue" }) {
  const pct = Math.min(100, (value / max) * 100)
  const bg = pct > 30 ? (color === "green" ? "bg-npc-green" : "bg-npc-blue") : "bg-npc-red"
  return (
    <div className="flex-1" title={`${value}/${max}`}>
      <div className="h-1 bg-neutral-800 rounded-full overflow-hidden">
        <div className={`h-full ${bg} rounded-full`} style={{ width: `${pct}%` }} />
      </div>
    </div>
  )
}

function ConnectionStatus({ connected, reconnecting }: { connected: boolean; reconnecting: boolean }) {
  if (connected) return (
    <span className="flex items-center gap-1.5">
      <span className="w-1.5 h-1.5 rounded-full bg-npc-green live-pulse" />
      <span className="text-npc-green text-[10px] uppercase tracking-wider">live</span>
    </span>
  )
  if (reconnecting) return (
    <span className="flex items-center gap-1.5">
      <span className="w-1.5 h-1.5 rounded-full bg-npc-orange live-pulse" />
      <span className="text-npc-orange text-[10px]">reconnecting</span>
    </span>
  )
  return (
    <span className="flex items-center gap-1.5">
      <span className="w-1.5 h-1.5 rounded-full bg-npc-red" />
      <span className="text-npc-red text-[10px]">offline</span>
    </span>
  )
}
