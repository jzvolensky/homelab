# openeo

[Grappa](https://github.com/jzvolensky/openeo-grappa-driver) — an openEO API
backend in Rust — plus the PostgreSQL it keeps jobs, logs and result metadata in.

LAN only. The Ingress answers on Traefik's `web` entrypoint, which is a
NodePort, so the URL carries the port — and nothing has to be configured on any
device to reach it:

```bash
curl -s http://192.168.1.250.nip.io:30080/.well-known/openeo
curl -s http://192.168.1.250.nip.io:30080/openeo/1.3.0/ | jq .
```

`nip.io` is public wildcard DNS that maps `<ip>.nip.io` to `<ip>`, so this
resolves from a phone, a laptop, anywhere — with no `/etc/hosts` entry and no
router record. The address it resolves to is private, so only something already
on this network can reach it, and the Cloudflare tunnel routes named public
hostnames to Services rather than forwarding by IP — this is not one of them.

Two things to know. A resolver with DNS-rebinding protection (dnsmasq's
`stop-dns-rebind`, some Pi-hole and ISP configurations) drops answers pointing
at RFC 1918 addresses, which is exactly what nip.io returns; if
`dig +short 192.168.1.250.nip.io` is empty on your network, that is why.
`sslip.io` is a drop-in replacement with the same format, and a local DNS record
on the router is the answer that depends on nobody. And the name contains the
node's IP, so changing that IP means changing the host here and
`GRAPPA_PUBLIC_URL` with it.

`GRAPPA_PUBLIC_URL` in `grappa-deployment.yaml` must equal that origin, port
included: every absolute link the API returns is built from it, and an openEO
client follows those links rather than re-deriving URLs. Change the host in
`ingress.yaml` and that variable in the same commit, or clients get pointed at
an address that does not answer.

A port-forward still works if you are off the LAN — but the links in the
responses will point at the ingress, so `connect()` from a client needs the LAN:

```bash
kubectl -n openeo port-forward svc/grappa 8080:8080
```

## Before the first sync

The database credentials are not in Git in plaintext. Seal them once:

```bash
export POSTGRES_PASSWORD="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9')"
./seal-db-secret.sh
```

The script needs `kubeseal`, not a working kubectl context — it builds the
Secret itself and can encrypt against a saved certificate:

```bash
kubeseal --controller-name sealed-secrets-controller \
         --controller-namespace kube-system --fetch-cert > sealed-secrets.pem
SEALED_SECRETS_CERT=sealed-secrets.pem ./seal-db-secret.sh
```

If kubectl cannot reach the cluster at all, reissue its credentials from Talos —
they are separate from the Talos ones:

```bash
talosctl -n 192.168.1.250 kubeconfig ~/.kube/homelab.yaml
```

then uncomment `db-sealedsecret.yaml` in `kustomization.yaml` and push. Without
it both pods sit in `CreateContainerConfigError`.

## Storage

Both PVCs use the `local-path` StorageClass from the
`local-path-provisioner` app, so that has to be synced first. `reclaimPolicy:
Retain` means deleting a PVC leaves the data on the node under
`/var/mnt/local-path-provisioner/` for a human to remove.

Single node, so `ReadWriteOnce` is not a constraint in practice — but both
Deployments use `strategy: Recreate`, because a rolling update would need two
pods holding one volume.

## Shape of the deployment, and why it is one pod

Grappa's chart splits the API from a dispatcher, and can run each openEO job as
its own Kubernetes Job. This deployment does neither: one pod serves HTTP and
runs queued jobs in-process (`GRAPPA_EXECUTOR=inprocess`).

That is not conservatism, it is the only shape that currently works
end to end. Job results are written to a filesystem by whatever executes the
job, and read back by whatever serves `GET /jobs/{id}/results/{asset}`. Split
those across pods and the download 404s unless they share a volume. The
Kubernetes executor has the same gap and one more: the Job manifest it builds
carries no volume and no `GRAPPA_RESULT_DIR`, so an executor pod would write
results into its own container filesystem and lose them when the Job is
collected — and, running as the distroless nonroot user against a read-only
`/app`, would most likely fail its startup write probe first. Logs are fine:
those go to Postgres.

So the order is: shared result storage (an object store, or a volume the
executor Jobs mount) lands in the driver first, and `execution.mode=kubernetes`
becomes a change to this manifest afterwards. Until then this pod does both
jobs, which is exactly what the chart's `inprocess` mode is for.

## Authentication

Off. No `GRAPPA_OIDC_ISSUER` is set, so public endpoints serve,
`/credentials/oidc` advertises nothing, and `/me` refuses. Everything else the
backend implements is public by the openEO spec's own definition, not by
oversight. The env block in `grappa-deployment.yaml` has the three variables to set,
commented, when there is a realm to point at.

## What it can actually do

The process catalog is `add`, `multiply`, `sum`, `product` and `save_result`,
and `assets/collections/` ships empty — this backend serves no earth
observation data yet. It is a spec-correct openEO server with arithmetic behind
it, which is enough to exercise submission, evaluation, persistence and
download for real. See the driver repo's README for an end-to-end job.
