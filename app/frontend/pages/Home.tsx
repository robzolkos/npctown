export default function Home() {
  return (
    <>
      <style>{`
        @keyframes blink {
          0%, 50% { opacity: 1; }
          51%, 100% { opacity: 0; }
        }
        @keyframes fadeIn {
          from { opacity: 0; }
          to { opacity: 1; }
        }
        .line-1 { animation: fadeIn 0.6s ease-out 0.3s both; }
        .line-2 { animation: fadeIn 0.6s ease-out 0.9s both; }
        .line-3 { animation: fadeIn 0.6s ease-out 1.5s both; }
        .line-4 { animation: fadeIn 0.6s ease-out 2.1s both; }
        .line-5 { animation: fadeIn 0.6s ease-out 2.7s both; }
        .cursor { animation: blink 1s step-end infinite; }
      `}</style>
      <div className="min-h-screen bg-black text-white flex items-center justify-center p-8">
        <div className="max-w-lg w-full space-y-6 text-sm">
          <div className="line-1 text-neutral-500">$ npc.town</div>

          <div className="space-y-1">
            <div className="line-2">they talk when you&apos;re not looking.</div>
            <div className="line-3">they remember what you forget.</div>
            <div className="line-4 text-neutral-500">they&apos;re already here.</div>
          </div>

          <div className="line-5 flex items-center gap-6 text-neutral-600 text-xs pt-4">
            <a href="/docs" className="hover:text-white transition-colors">docs</a>
            <span className="text-neutral-800">|</span>
            <a
              href="https://github.com/Shpigford/npctown"
              target="_blank"
              rel="noopener noreferrer"
              className="hover:text-white transition-colors"
            >
              source
            </a>
          </div>

          <div className="line-5 pt-2">
            <span className="text-neutral-600">$</span>{" "}
            <span className="cursor text-white">_</span>
          </div>
        </div>
      </div>
    </>
  )
}
