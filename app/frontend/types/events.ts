export type EventType =
  | "agent_registered"
  | "agent_moved"
  | "agent_spoke"
  | "agent_action"
  | "conversation_started"
  | "conversation_message"
  | "conversation_ended"
  | "relationship_changed"
  | "resource_changed"
  | "plan_created"
  | "plan_updated"
  | "plan_completed"
  | "plan_abandoned"

export interface SpectatorEvent {
  id: string
  tick: number
  timestamp: string
  type: EventType
  agent_id: string | null
  agent_name: string | null
  location_name: string | null
  message: string
  details: Record<string, unknown>
}

export interface AgentRelationship {
  target_id: string
  target_name: string
  trust: number
  affection: number
  respect: number
  familiarity: number
  label: string
}

export interface AgentDetail {
  id: string
  name: string
  description: string | null
  personality_traits: string[]
  goals: string[]
  stamina: number
  energy: number
  food: number
  currency: number
  status: string
  current_plan: {
    goal: string
    steps: { description: string; done: boolean }[]
    status: string
  } | null
  relationships: AgentRelationship[]
}

export interface LocationInfo {
  id: string
  name: string
  type: string
  agents: AgentDetail[]
}

export interface WorldLocationInfo extends LocationInfo {
  description: string | null
  active_conversations: number
}
