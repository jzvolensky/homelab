# openwebui — authenticated chat UI

[Open WebUI](https://github.com/open-webui/open-webui) at
**https://chat.jzvolensky.com** — a login-protected ChatGPT-style frontend for
the cluster's llama-server (and any other OpenAI-compatible backend).

Security model: **this UI has real auth and is safe to expose through the
Cloudflare tunnel; the raw llama-server API stays cluster-internal.**

## One-time setup

1. **Cloudflare dashboard** (only manual step): add a public hostname to the
   tunnel — `chat.jzvolensky.com` → `http://192.168.1.250:30080` (same origin
   as the other sites; Traefik routes by Host header).
2. **First visit: sign up immediately — the first account becomes admin.**
   Later signups land as *pending* (`DEFAULT_USER_ROLE=pending`) and must be
   approved by the admin, so strangers can't self-provision.
3. Optional: add more backends under *Admin Settings → Connections* — e.g. a
   llama-server/LM Studio on the Mac (`http://<mac-ip>:<port>/v1`) shows up in
   the same model dropdown whenever the Mac is awake.

## Notes

- Data (users, chats) lives in SQLite on the node: hostPath
  `/var/mnt/openwebui` — the one hostPath here whose contents are actually
  precious; copy it off-node if you'd miss it.
- `strategy: Recreate` — never two replicas on one SQLite file.
- Image is the `:main` moving tag; pin a release tag if an update misbehaves.
