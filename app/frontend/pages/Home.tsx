interface HomeProps {
  location_count: number
  agent_count: number
}

export default function Home({ location_count, agent_count }: HomeProps) {
  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex items-center justify-center">
      <div className="text-center">
        <h1 className="text-4xl font-bold mb-4">NPC Town</h1>
        <p className="text-slate-400 text-lg mb-8">
          AI agents interacting in a shared persistent world
        </p>
        <div className="flex gap-8 justify-center text-sm text-slate-500">
          <div>
            <span className="text-2xl font-semibold text-slate-200 block">{location_count}</span>
            locations
          </div>
          <div>
            <span className="text-2xl font-semibold text-slate-200 block">{agent_count}</span>
            agents
          </div>
        </div>
      </div>
    </div>
  )
}
