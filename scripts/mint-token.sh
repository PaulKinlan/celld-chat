#!/bin/bash
# mint an exe.dev API token with the local key (key must be registered via `ssh exe.dev ssh-key add`)
# usage: mint-token.sh '<permissions-json>' [namespace]
set -e
PERMISSIONS="${1:-{\}}"
NS="${2:-v0@exe.dev}"
KEY="${KEY:-$HOME/.ssh/id_ed25519}"
b64url() { tr -d '\n=' | tr '+/' '-_'; }
PAYLOAD=$(printf '%s' "$PERMISSIONS" | base64 | b64url)
SIG=$(printf '%s' "$PERMISSIONS" | ssh-keygen -Y sign -f "$KEY" -n "$NS")
SIGBLOB=$(echo "$SIG" | sed '1d;$d' | b64url)
echo "exe0.$PAYLOAD.$SIGBLOB"
