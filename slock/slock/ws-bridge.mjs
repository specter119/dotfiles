{{!-- dotter: copy as template so node resolves node_modules from target dir --}}
import { createServer } from "node:http";
import WebSocket, { WebSocketServer } from "ws";
import { HttpsProxyAgent } from "https-proxy-agent";

const args = process.argv.slice(2);
const readArg = (name) => {
  const index = args.indexOf(name);
  if (index === -1) {
    return undefined;
  }
  return args[index + 1];
};

const UPSTREAM = process.env.SLOCK_UPSTREAM || "https://api.slock.ai";
const PORT = parseInt(process.env.SLOCK_BRIDGE_PORT || "19280", 10);
const PROXY = readArg("--proxy");

if (!PROXY) {
  console.error("[bridge] Missing --proxy argument, exiting.");
  process.exit(1);
}

const agent = new HttpsProxyAgent(PROXY);
const masked = PROXY.replace(/\/\/[^@]*@/, "//***@");
console.log(`[bridge] proxy=${masked} upstream=${UPSTREAM} port=${PORT}`);

const server = createServer((_req, res) => {
  res.writeHead(200);
  res.end("slock ws bridge\n");
});

const wss = new WebSocketServer({ server });

wss.on("connection", (local, req) => {
  const path = req.url || "/";
  const upstreamUrl = UPSTREAM.replace(/^http/, "ws") + path;
  console.log(`[bridge] new connection -> ${upstreamUrl.split("?")[0]}...`);

  const remote = new WebSocket(upstreamUrl, { agent });

  remote.on("open", () => {
    console.log("[bridge] upstream connected");
  });

  local.on("message", (data, isBinary) => {
    if (remote.readyState === WebSocket.OPEN) {
      remote.send(data, { binary: isBinary });
    }
  });

  remote.on("message", (data, isBinary) => {
    if (local.readyState === WebSocket.OPEN) {
      local.send(data, { binary: isBinary });
    }
  });

  local.on("close", (code, reason) => {
    console.log(`[bridge] local closed code=${code}`);
    if (remote.readyState <= WebSocket.OPEN) {
      remote.close(code, reason);
    }
  });

  remote.on("close", (code, reason) => {
    console.log(`[bridge] upstream closed code=${code}`);
    if (local.readyState <= WebSocket.OPEN) {
      local.close(code, reason);
    }
  });

  local.on("error", (err) => {
    console.error("[bridge] local error:", err.message);
    if (remote.readyState <= WebSocket.OPEN) {
      remote.close();
    }
  });

  remote.on("error", (err) => {
    console.error("[bridge] upstream error:", err.message);
    if (local.readyState <= WebSocket.OPEN) {
      local.close();
    }
  });
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`[bridge] listening on 127.0.0.1:${PORT}`);
});

for (const sig of ["SIGTERM", "SIGINT"]) {
  process.on(sig, () => {
    console.log(`[bridge] ${sig} received, shutting down`);
    wss.close();
    server.close();
    process.exit(0);
  });
}
