# argocd-config — expose Argo CD at argocd.jzvolensky.com with GitHub login

Argo CD self-manages its own config here (GitOps). Traffic path:

```
browser → Cloudflare (TLS) → cloudflared (Talos node ext) → Traefik :30080 → Ingress → argocd-server:80
```

Manifests:
- `argocd-cm.yaml` — external `url` + Dex GitHub connector
- `argocd-cmd-params-cm.yaml` — `server.insecure: "true"` (Cloudflare does TLS)
- `argocd-rbac-cm.yaml` — `jzvolensky` → admin, others read-only
- `argocd-ingress.yaml` — Traefik Ingress for `argocd.jzvolensky.com`
- `github-oauth-sealedsecret.yaml` — **you generate this** (see below)

## One-time setup

### 1. Re-seal the GitHub OAuth client secret
```bash
export KUBECONFIG=~/.kube/homelab.yaml
export GITHUB_CLIENT_SECRET='<client secret of GitHub OAuth app Ov23lixAkPtlc2fa5uOI>'
./reseal-github-oauth.sh
# then uncomment github-oauth-sealedsecret.yaml in kustomization.yaml
```

### 2. GitHub OAuth app callback URL
In the GitHub OAuth app settings, ensure the **Authorization callback URL** is:
`https://argocd.jzvolensky.com/api/dex/callback` (same domain as before, so likely already set).

### 3. Cloudflare tunnel public hostname
In the Cloudflare Zero Trust dashboard → your tunnel (the one whose token is in
`ext-cloudflared`) → **Public Hostnames → Add**:
- Subdomain `argocd`, domain `jzvolensky.com`
- Service: **HTTP** → `localhost:30080` (cloudflared runs on the node; Traefik's
  NodePort is 30080). If that can't reach it, try `<node-ip>:30080` = `192.168.1.250:30080`.
- Add a DNS CNAME `argocd` → the tunnel (the dashboard offers to do this automatically).

### 4. Restart argocd-server (one-time, for server.insecure)
`server.insecure` is a startup param, so after the config first syncs:
```bash
kubectl -n argocd rollout restart deploy/argocd-server deploy/argocd-dex-server
```

## Verify
```bash
kubectl get ingress -n argocd
kubectl get pods -n traefik
curl -H 'Host: argocd.jzvolensky.com' http://192.168.1.250:30080/healthz   # -> ok
```
Then browse https://argocd.jzvolensky.com and "Log in via GitHub".

> Argo CD adopts its own pre-existing ConfigMaps on first sync — expect them to go
> from OutOfSync to Synced. The bootstrap `admin` login keeps working alongside GitHub.
