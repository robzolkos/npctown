import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"
import tailwindcss from "@tailwindcss/vite"
import RubyPlugin from "vite-plugin-ruby"
import path from "path"

export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
    RubyPlugin(),
  ],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./app/frontend"),
    },
  },
  optimizeDeps: {
    include: [
      "react",
      "react-dom",
      "@inertiajs/react",
    ],
  },
  server: {
    hmr: {
      host: "127.0.0.1",
      protocol: "ws",
      port: Number(process.env.VITE_RUBY_PORT) || 3036,
      clientPort: Number(process.env.VITE_RUBY_PORT) || 3036,
    },
  },
})
