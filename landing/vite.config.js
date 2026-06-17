import { defineConfig } from "vite";

// Abendrot landing — static build for abendrot.app (PREVIEW only).
// Outputs a fully static site to ./dist. No SSR, no runtime framework.
// Vercel-ready (see vercel.json) but DO NOT deploy — live deploy is the founder's gate.
export default defineConfig({
  root: ".",
  base: "./",
  build: {
    outDir: "dist",
    assetsDir: "assets",
    target: "es2022",
    cssMinify: true,
    // Vite 8 (Rolldown) minifies with its native minifier by default — no esbuild dep needed.
    minify: true,
    sourcemap: false,
    rollupOptions: {
      output: {
        // Stable, cache-friendly hashed asset names.
        entryFileNames: "assets/[name]-[hash].js",
        chunkFileNames: "assets/[name]-[hash].js",
        assetFileNames: "assets/[name]-[hash][extname]",
      },
    },
  },
  server: {
    port: 4317,
    open: false,
  },
});
