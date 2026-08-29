# celld-chat

A distributed chat app: Vite frontend + Durable Object backend running on
[celld](https://celld.dev) — self-hosted, distributed Durable Objects — deployed
across two [exe.dev](https://exe.dev) VMs.

## Architecture

- **App**: one celld *cell* (Durable Object) per chat room. Holds WebSocket
  connections (hibernatable), stores history in its private SQLite database.
- **Fleet**: two exe.dev VMs (`celld-chat-e`, `celld-chat-f`) each run a celld
  node sharing one S3 bucket. The bucket is the coordinator: node discovery,
  cell ownership (conditional writes), replication, and deployments.
- **Distribution**: a user on VM-E and a user on VM-F land in the same room;
  the room's cell lives on exactly one node and requests from the other node
  are proxied to it. Writes replicate to the peer before being acknowledged.
- **Frontend**: Vite-built static assets served by the Worker from the same
  deployment (`ASSETS` binding).

```
browser ──wss──> celld-chat-e.exe.xyz (node A) ──┐
                                                  ├── S3 bucket (leases, replicas, deploys)
browser ──wss──> celld-chat-f.exe.xyz (node B) ──┘
```

## Develop

```
npm install
npm run build      # vite -> target/
celld dev          # local node on http://127.0.0.1:9876
```

Note: the `celld dev` file watcher (v0.4.0) restarts on `.celld/` writes
despite the documented ignore; long-lived multi-client WS testing locally is
unreliable — test against a fleet.

## Deploy

```
export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...   # scoped to the bucket
npm run build
celld deploy . --bucket s3://paul-celld-fleet-euw2 --region eu-west-2
```

Nodes poll the deployment pointer every 30s and adopt in place, without a
restart and without dropping WebSocket connections (hibernatable sockets are
kept across the code move).
