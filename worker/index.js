// Chat room Durable Object: one cell per room. Holds WebSockets, stores
// history in its private SQLite DB, replicates across the celld fleet.
export class ChatRoom {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.sql = ctx.storage.sql;
    this.sql.exec(
      `CREATE TABLE IF NOT EXISTS messages (
         id INTEGER PRIMARY KEY AUTOINCREMENT,
         name TEXT NOT NULL,
         text TEXT NOT NULL,
         ts INTEGER NOT NULL
       )`
    );
  }

  history() {
    const rows = [
      ...this.sql.exec(`SELECT name, text, ts FROM messages ORDER BY id DESC LIMIT 100`),
    ].reverse();
    return rows.map(([name, text, ts]) => ({ name, text, ts }));
  }

  broadcast(msg) {
    const data = JSON.stringify(msg);
    for (const ws of this.ctx.getWebSockets()) {
      try {
        ws.send(data);
      } catch {
        // client gone; close event will clean up
      }
    }
  }

  presence() {
    this.broadcast({ type: "presence", count: this.ctx.getWebSockets().length });
  }

  async fetch(request) {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("websocket upgrade required", { status: 426 });
    }
    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[0]);
    pair[0].send(JSON.stringify({ type: "history", messages: this.history() }));
    this.presence();
    return new Response(null, { status: 101, webSocket: pair[1] });
  }

  async webSocketMessage(ws, raw) {
    let name = "anon";
    let text = "";
    try {
      const m = JSON.parse(raw);
      name = String(m.name || "anon").slice(0, 40);
      text = String(m.text || "").slice(0, 500);
    } catch {
      return;
    }
    if (!text.trim()) return;
    const ts = Date.now();
    this.sql.exec(`INSERT INTO messages (name, text, ts) VALUES (?, ?, ?)`, name, text, ts);
    // keep history bounded
    this.sql.exec(
      `DELETE FROM messages WHERE id NOT IN (SELECT id FROM messages ORDER BY id DESC LIMIT 500)`
    );
    this.broadcast({ type: "chat", name, text, ts });
  }

  async webSocketClose() {
    this.presence();
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const m = url.pathname.match(/^\/api\/room\/([^/]+)\/ws$/);
    if (m) {
      const name = decodeURIComponent(m[1]).slice(0, 64);
      const room = env.ROOM.get(env.ROOM.idFromName(name));
      return room.fetch(request);
    }
    return env.ASSETS.fetch(request);
  },
};
