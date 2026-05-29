# Nemotron 3 Super NIM on 2x H100

This runbook deploys NVIDIA Nemotron 3 Super 120B A12B with Docker on a Linux host with two H100 80GB GPUs.

## Recommended Image and Profile

Use the regular Nemotron 3 Super NIM, not the Turbo image, for this 2x H100 target. NGC tag `2.0.5` currently exposes an amd64 image at this digest:

```bash
nvcr.io/nim/nvidia/nemotron-3-super-120b-a12b@sha256:e24028cbc5bf3b3c1755ad37f898a0cd954845ab8c7012eb490aed4ac55b44ea
```

That digest is used by default because some Docker/NGC combinations fail near the end of a tag-based `2.0.5` pull with `error from registry: Incorrect Repository Format`.

For two H100s, use the FP8 tensor-parallel 2 profile returned by `list-model-profiles` on this image:

```bash
DOCKER_PLATFORM=linux/amd64
NIM_MODEL_PROFILE=57d42cc7d33914933427e7f8d8cb1773bc11e5c96826c92095820a8776e6a4f6
NIM_MAX_MODEL_LEN=32768
NIM_KVCACHE_PERCENT=0.9
NIM_PASSTHROUGH_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
```

That profile ID maps to `vllm-fp8-tp2-pp1-65.0` and requires at least 65 GB/GPU. The `NIM_MAX_MODEL_LEN=32768` cap is important for two-GPU deployments. The full BF16 model is much heavier, so FP8 is the sensible target for two H100 80GB GPUs.

The `NIM_PASSTHROUGH_ARGS` line enables OpenAI-compatible tool calling. This is required for clients such as opencode that send `tool_choice: "auto"`.

The separate Turbo image, `nvcr.io/nim/nvidia/nemotron-3-super-120b-a12b-turbo:1.0.0`, exists, but NVIDIA's current Turbo support matrix lists B200/NVFP4 and H200/FP8 configurations rather than 2x H100. Keep Turbo as a later experiment, not the default for this host.

## 1. Host Checks

On the H100 host:

```bash
nvidia-smi -L
docker --version
docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi
df -h /data
```

You should see both H100s in the host and container output. NIM for LLMs does not support MIG mode, so disable MIG if it is enabled. Keep plenty of free disk in the cache path; the FP8 model artifacts are large.

## 2. NGC Access

Create an NGC Personal API Key with NGC Catalog access and accept the Nemotron 3 Super NIM terms in the NVIDIA NGC catalog.

Use `.env.super.example` as a template:

```bash
cp .env.super.example .env.super
chmod 600 .env.super
vi .env.super
```

Put the real `NGC_API_KEY` in `.env.super`. The Super script loads `.env.super` by default so it does not collide with the Nano `.env.nano` settings.

Values passed before the command override `.env.super`, so this works as expected:

```bash
LIST_PROFILES=1 bash ./deploy-nemotron3-super-nim.sh
```

You can also log in manually:

```bash
echo "$NGC_API_KEY" | docker login nvcr.io --username '$oauthtoken' --password-stdin
```

## 3. Confirm the Profile

Before the first full launch, ask the container which profiles are visible on this host:

```bash
LIST_PROFILES=1 bash ./deploy-nemotron3-super-nim.sh
```

Look for `vllm-fp8-tp2-pp1-65.0` under "Compatible with system and runnable". If the host has more than two GPUs, restrict visibility to the pair you want:

```bash
GPU_DEVICES=0,1 LIST_PROFILES=1 bash ./deploy-nemotron3-super-nim.sh
```

## 4. Run

From this folder on the H100 host:

```bash
bash ./deploy-nemotron3-super-nim.sh
```

If the host has more than two GPUs:

```bash
GPU_DEVICES=0,1 bash ./deploy-nemotron3-super-nim.sh
```

If a previous Super container exists and you intentionally want to replace it:

```bash
RECREATE=1 bash ./deploy-nemotron3-super-nim.sh
```

## 5. Health Check

Startup can take a while while the container downloads and prepares model artifacts.

```bash
docker logs -f nemotron3-super-nim
curl -fsS http://localhost:8000/v1/health/ready
curl -s http://localhost:8000/v1/models
```

## 6. Smoke Test

Use the model id returned by `/v1/models`; it is expected to be `nvidia/nemotron-3-super-120b-a12b`.

```bash
MODEL="$(curl -s http://localhost:8000/v1/models | jq -r '.data[0].id')"

curl -s http://localhost:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d "{
    \"model\": \"$MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Give me a concise checklist for validating a new NIM deployment.\"}],
    \"temperature\": 1.0,
    \"top_p\": 0.95,
    \"max_tokens\": 512,
    \"chat_template_kwargs\": {\"enable_thinking\": false}
}" | jq .
```

## 7. Quick Performance Check

For a quick tokens/sec read, run:

```bash
python3 ./bench-nim-tps.py --requests 4 --concurrency 1 --max-tokens 512
```

For an aggregate throughput check with concurrent requests:

```bash
python3 ./bench-nim-tps.py --requests 8 --concurrency 2 --max-tokens 512
```

The script reports wall-clock output tokens/sec from `usage.completion_tokens`. If `NIM_PER_REQ_METRICS_ENABLE=1` was set when the container started, it also reports NIM's own `stats.response_tokens.tokens_per_second`.

For low-effort reasoning:

```bash
curl -s http://localhost:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d "{
    \"model\": \"$MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Analyze the main risks in this deployment.\"}],
    \"temperature\": 1.0,
    \"top_p\": 0.95,
    \"max_tokens\": 1024,
    \"chat_template_kwargs\": {\"enable_thinking\": true, \"low_effort\": true}
  }" | jq .
```

## Troubleshooting

If `docker pull` says to accept the license, open the NGC catalog page for Nemotron 3 Super and accept the governing terms with the same NGC account used for the API key.

If Docker cannot see the GPUs, install or reconfigure the NVIDIA Container Toolkit, restart Docker, and rerun:

```bash
docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi
```

If a tag-based `docker pull` fails near the end with `error from registry: Incorrect Repository Format`, pull the amd64 digest directly:

```bash
docker pull --platform linux/amd64 nvcr.io/nim/nvidia/nemotron-3-super-120b-a12b@sha256:e24028cbc5bf3b3c1755ad37f898a0cd954845ab8c7012eb490aed4ac55b44ea
```

The deployment script sets both `DOCKER_PLATFORM=linux/amd64` and the amd64 digest by default for this reason. If digest pulling also fails, upgrade Docker before retrying.

If the container OOMs or fails profile selection, verify that `NIM_MODEL_PROFILE=57d42cc7d33914933427e7f8d8cb1773bc11e5c96826c92095820a8776e6a4f6` and `NIM_MAX_MODEL_LEN=32768` are set. You can also try reducing `NIM_KVCACHE_PERCENT` to `0.85` or lowering `NIM_MAX_MODEL_LEN` to `16384`.

If the Nano container is still running on the same two GPUs, stop it before starting Super:

```bash
docker rm -f nemotron3-nano-nim
```

If the Super container exits during startup, check:

```bash
docker logs --tail=200 nemotron3-super-nim
```
