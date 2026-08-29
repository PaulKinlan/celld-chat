const $ = (id) => document.getElementById(id);
const room = location.hash.slice(1) || "lobby";
$("room").textContent = room;
$("node").textContent = location.host;

const name = $("name");
name.value = localStorage.getItem("chat-name") || "";
name.addEventListener("change", () => localStorage.setItem("chat-name", name.value));

const msgs = $("msgs");
function add(cls, who, body) {
  const el = document.createElement("div");
  el.className = cls;
  el.innerHTML =
    cls === "msg" ? `<div class="who"></div><div class="body"></div>` : ``;
  if (cls === "msg") {
    el.querySelector(".who").textContent = who;
    el.querySelector(".body").textContent = body;
  } else {
    el.textContent = body;
  }
  msgs.append(el);
  msgs.scrollTop = msgs.scrollHeight;
}

let ws;
let retry = 0;
function connect() {
  const proto = location.protocol === "https:" ? "wss" : "ws";
  ws = new WebSocket(`${proto}://${location.host}/api/room/${encodeURIComponent(room)}/ws`);
  ws.onopen = () => {
    retry = 0;
    $("status").textContent = "live";
    $("status").className = "on";
  };
  ws.onclose = () => {
    $("status").textContent = "reconnecting…";
    $("status").className = "off";
    setTimeout(connect, Math.min(1000 * 2 ** retry++, 15000));
  };
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    if (m.type === "history") {
      msgs.innerHTML = "";
      for (const msg of m.messages) add("msg", msg.name, msg.text);
    } else if (m.type === "chat") {
      add("msg", m.name, m.text);
    } else if (m.type === "presence") {
      $("presence").textContent = `${m.count} online`;
    }
  };
}
connect();

$("f").addEventListener("submit", (e) => {
  e.preventDefault();
  const text = $("text").value.trim();
  if (!text || ws.readyState !== 1) return;
  ws.send(JSON.stringify({ name: name.value || "anon", text }));
  $("text").value = "";
});
