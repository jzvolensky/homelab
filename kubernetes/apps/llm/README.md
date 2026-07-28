# llm — llama.cpp server (OpenAI-compatible API)

Runs [llama.cpp](https://github.com/ggml-org/llama.cpp) `llama-server`, exposing
an OpenAI-compatible API **cluster-internal only** (no ingress on purpose — an
unauthenticated LLM API should not go through the cloudflared tunnel).

- In-cluster endpoint: `http://llama-server.llm.svc.cluster.local/v1`
- Models are downloaded from Hugging Face on first start and cached on the node
  at `/var/mnt/models` (hostPath — fine on a single-node cluster, survives
  restarts). Currently deploying **Qwen3-0.6B Q8_0** (~0.6 GB) as a fast smoke
  test; the intended daily driver is **Qwen3-8B Q4_K_M** (~5 GB) — swap the
  `-hf` arg in `deployment.yaml` once GPU inference is verified.

## Test it

```bash
kubectl -n llm port-forward svc/llama-server 8080:80
curl http://localhost:8080/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "qwen3-8b",
  "messages": [{"role": "user", "content": "Hello! /no_think"}]
}'
```

From the website (webserver-rs pod), point any OpenAI client at
`http://llama-server.llm.svc.cluster.local/v1` with any non-empty API key.

## Swapping models

Models are fetched by the `fetch-model` initContainer (plain curl + SHA-256
verification — llama-server's built-in `-hf` downloader corrupted reads on this
image and is deliberately not used). To swap, edit `deployment.yaml` in two
places, keeping them consistent:

1. the initContainer env: `MODEL_URL` (the HF `resolve/main` file URL),
   `MODEL_SHA256` (shown on the file's HF page), `MODEL_FILE`;
2. the `-m /models/<MODEL_FILE>` arg (and `--alias`).

Old model files stay in `/var/mnt/models` — clean them up manually if disk
matters. Sizing rule of thumb:
GGUF file size + ~1–2 GB for KV cache/buffers must fit inside the pod memory
limit, and the limit must fit inside the VM (currently 16 GB, shared with the
control plane). On CPU, prefer small dense models (4–9B Q4) or small-MoE models.
Bigger MoE models (e.g. 30B-A3B class, ~18 GB) need `vm_memory` bumped in
`infra/terraform` first.

## GPU setup (done July 2026)

Inference runs on the Radeon 780M iGPU via **Vulkan** (RADV). The chain that
makes `/dev/dri/renderD128` exist inside the pod:

1. **Proxmox host**: iGPU (`0000:c4:00.0`, `1002:15bf`) bound to vfio-pci
   (`/etc/modprobe.d/vfio.conf` + amdgpu blacklisted). Host HDMI console is
   dead by design.
2. **VM 100**: `machine: q35`, `hostpci0: 0000:c4:00.0,pcie=1`, memory pinned
   at 20 GB (passthrough pins guest RAM; host keeps the rest). Mirrored in
   `infra/terraform/vm.tf`.
3. **Talos**: schematic `f11afbd…` already ships the `amdgpu` extension
   (driver + firmware) — no image change was needed.

GPU memory budget: 2 GB VRAM carve-out (BIOS UMA) + ~10 GB GTT (driver default,
half of guest RAM) ≈ **12 GB ceiling for model + KV cache**. On an APU both are
the same DRAM, so the split doesn't matter for speed. If a bigger model won't
load: raise the BIOS UMA carve-out, or add `amdgpu.gttsize=` via Talos kernel
args.

Verify the GPU is actually used (look for `ggml_vulkan: Found 1 Vulkan devices`
naming PHOENIX/RADV — if it falls back to CPU it logs no Vulkan device and
runs ~5x slower):

```bash
kubectl -n llm logs deploy/llama-server | grep -i vulkan
```

Known quirk: AMD iGPUs don't always reset cleanly across VM restarts. If the
GPU wedges after a VM reboot (Vulkan init errors in the pod), reboot the
Proxmox host.

## Notes

- Namespace is labeled `pod-security.kubernetes.io/enforce: privileged` because
  Talos's default *baseline* PSS forbids hostPath volumes.
- `strategy: Recreate` — two replicas can't hold two model copies in 16 GB.
- The `:server` image tag is a moving tag; pin to a `server-b####` build tag if
  an update ever breaks things.
