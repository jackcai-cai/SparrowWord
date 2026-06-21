import path from "node:path";
import { fileURLToPath } from "node:url";

import type { NextConfig } from "next";

const configDirectory = path.dirname(fileURLToPath(import.meta.url));
const workspaceRoot = path.join(configDirectory, "..", "..");
const usePolling = process.env.SPARROWWORD_WATCH_POLLING === "1";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  allowedDevOrigins: ["127.0.0.1"],
  turbopack: {
    root: workspaceRoot,
  },
  ...(usePolling
    ? {
        watchOptions: {
          pollIntervalMs: 1000,
        },
      }
    : {}),
};

export default nextConfig;
