# 04 — Cloudflare Tunnel (in-cluster)

You want your website reachable without port-forwarding or exposing your home IP.
`cloudflared` runs **inside the cluster** as a Deployment and dials *out* to
Cloudflare — no inbound ports, works behind NAT, and fits Talos perfectly (it's
just a container, nothing on the host).

## One-time Cloudflare setup

1. In the [Cloudflare Zero Trust dashboard](https://one.dash.cloudflare.com):
   **Networks → Tunnels → Create a tunnel** (type: *Cloudflared*).
2. Copy the tunnel **token**.
3. Add public hostname(s) mapping your domain → an in-cluster Service, e.g.
   `yoursite.com → http://webserver.default.svc.cluster.local:80`.

## Deploy in-cluster (GitOps)

Store the tunnel token as a sealed secret and run the official chart or a plain
Deployment. Sketch of a GitOps app under `kubernetes/apps/cloudflared/`:

```yaml
# application.yaml — Helm chart route (recommended)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cloudflared
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://cloudflare.github.io/helm-charts
    chart: cloudflare-tunnel-remote      # token-based ("remote") tunnels
    targetRevision: 0.3.2                 # check the repo for the latest
    helm:
      valuesObject:
        cloudflare:
          # reference the sealed-secret you created, don't inline the token
          tunnelTokenSecret: cloudflared-token
  destination:
    server: https://kubernetes.default.svc
    namespace: cloudflared
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true]
```

Seal the token:

```bash
kubectl create secret generic cloudflared-token \
  --namespace cloudflared \
  --from-literal=tunnelToken='<TOKEN>' --dry-run=client -o yaml \
| kubeseal --controller-name sealed-secrets --controller-namespace kube-system \
  -o yaml > kubernetes/apps/cloudflared/cloudflared-token-sealed.yaml
```

Commit both files, add the app to `kubernetes/apps/kustomization.yaml`, push.
Argo CD deploys it and the tunnel comes up outbound-only.

> Tailscale (already in your stack) and Cloudflare Tunnel coexist fine — Tailscale
> for private admin access (kubectl, Argo CD UI), Cloudflare Tunnel for the public
> website.
