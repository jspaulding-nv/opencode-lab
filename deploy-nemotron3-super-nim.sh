#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env.super}"
tracked_env=(
  IMAGE
  CONTAINER_NAME
  HOST_PORT
  LOCAL_NIM_CACHE
  SHM_SIZE
  DOCKER_PLATFORM
  GPU_DEVICES
  NIM_MODEL_PROFILE
  NIM_MAX_MODEL_LEN
  NIM_KVCACHE_PERCENT
  NIM_PASSTHROUGH_ARGS
  NIM_PER_REQ_METRICS_ENABLE
  RECREATE
  LIST_PROFILES
  SKIP_DOCKER_LOGIN
  NGC_API_KEY
  NIM_LOG_LEVEL
  CUDA_LAUNCH_BLOCKING
)
env_overrides=()
for name in "${tracked_env[@]}"; do
  if [[ -n "${!name+x}" ]]; then
    env_overrides+=("$(declare -p "$name")")
  fi
done

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

for override in "${env_overrides[@]}"; do
  eval "$override"
done

IMAGE="${IMAGE:-nvcr.io/nim/nvidia/nemotron-3-super-120b-a12b@sha256:e24028cbc5bf3b3c1755ad37f898a0cd954845ab8c7012eb490aed4ac55b44ea}"
CONTAINER_NAME="${CONTAINER_NAME:-nemotron3-super-nim}"
HOST_PORT="${HOST_PORT:-8000}"
LOCAL_NIM_CACHE="${LOCAL_NIM_CACHE:-/data/nim-cache/nemotron-3-super-120b-a12b}"
SHM_SIZE="${SHM_SIZE:-32g}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
GPU_DEVICES="${GPU_DEVICES:-}"
NIM_MODEL_PROFILE="${NIM_MODEL_PROFILE:-57d42cc7d33914933427e7f8d8cb1773bc11e5c96826c92095820a8776e6a4f6}"
NIM_MAX_MODEL_LEN="${NIM_MAX_MODEL_LEN:-32768}"
NIM_KVCACHE_PERCENT="${NIM_KVCACHE_PERCENT:-0.9}"
RECREATE="${RECREATE:-0}"
LIST_PROFILES="${LIST_PROFILES:-0}"
SKIP_DOCKER_LOGIN="${SKIP_DOCKER_LOGIN:-0}"

if [[ -z "${NGC_API_KEY:-}" || "$NGC_API_KEY" == "paste_your_ngc_api_key_here" ]]; then
  echo "NGC_API_KEY is not set. Export it or put it in .env.super, then rerun this script." >&2
  exit 1
fi

command -v docker >/dev/null || {
  echo "docker was not found on PATH." >&2
  exit 1
}

command -v nvidia-smi >/dev/null || {
  echo "nvidia-smi was not found on PATH. Check the NVIDIA driver installation." >&2
  exit 1
}

echo "Checking visible GPUs..."
nvidia-smi -L

if [[ ! -d "$LOCAL_NIM_CACHE" ]]; then
  if mkdir -p "$LOCAL_NIM_CACHE" 2>/dev/null; then
    :
  elif command -v sudo >/dev/null; then
    sudo mkdir -p "$LOCAL_NIM_CACHE"
    sudo chown -R "$(id -u):$(id -g)" "$LOCAL_NIM_CACHE"
  else
    echo "Could not create LOCAL_NIM_CACHE=$LOCAL_NIM_CACHE. Create it manually or choose a writable path." >&2
    exit 1
  fi
fi
chmod -R a+w "$LOCAL_NIM_CACHE"

if [[ "$SKIP_DOCKER_LOGIN" != "1" ]]; then
  echo "Logging in to nvcr.io with NGC_API_KEY..."
  echo "$NGC_API_KEY" | docker login nvcr.io --username '$oauthtoken' --password-stdin
fi

echo "Pulling $IMAGE..."
docker pull --platform "$DOCKER_PLATFORM" "$IMAGE"

gpu_args=(--gpus all)
if [[ -n "$GPU_DEVICES" ]]; then
  gpu_args=(--gpus "device=$GPU_DEVICES")
fi

if [[ "$LIST_PROFILES" == "1" ]]; then
  echo "Listing model profiles for the visible GPUs..."
  docker run --rm \
    --platform "$DOCKER_PLATFORM" \
    --runtime=nvidia \
    "${gpu_args[@]}" \
    -e NGC_API_KEY \
    -v "$LOCAL_NIM_CACHE:/opt/nim/.cache" \
    -u "$(id -u)" \
    "$IMAGE" \
    list-model-profiles
  exit 0
fi

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  if [[ "$RECREATE" == "1" ]]; then
    echo "Removing existing container $CONTAINER_NAME..."
    docker rm -f "$CONTAINER_NAME"
  else
    echo "Container $CONTAINER_NAME already exists. Set RECREATE=1 to replace it." >&2
    exit 1
  fi
fi

env_args=(
  -e NGC_API_KEY
  -e NIM_MODEL_PROFILE="$NIM_MODEL_PROFILE"
  -e NIM_MAX_MODEL_LEN="$NIM_MAX_MODEL_LEN"
  -e NIM_KVCACHE_PERCENT="$NIM_KVCACHE_PERCENT"
)

if [[ -n "${NIM_LOG_LEVEL:-}" ]]; then
  env_args+=(-e NIM_LOG_LEVEL="$NIM_LOG_LEVEL")
fi

if [[ -n "${CUDA_LAUNCH_BLOCKING:-}" ]]; then
  env_args+=(-e CUDA_LAUNCH_BLOCKING="$CUDA_LAUNCH_BLOCKING")
fi

if [[ -n "${NIM_PASSTHROUGH_ARGS:-}" ]]; then
  env_args+=(-e NIM_PASSTHROUGH_ARGS="$NIM_PASSTHROUGH_ARGS")
fi

if [[ -n "${NIM_PER_REQ_METRICS_ENABLE:-}" ]]; then
  env_args+=(-e NIM_PER_REQ_METRICS_ENABLE="$NIM_PER_REQ_METRICS_ENABLE")
fi

echo "Starting $CONTAINER_NAME on host port $HOST_PORT..."
echo "Using NIM_MODEL_PROFILE=$NIM_MODEL_PROFILE, NIM_MAX_MODEL_LEN=$NIM_MAX_MODEL_LEN"
docker run -d \
  --platform "$DOCKER_PLATFORM" \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  --runtime=nvidia \
  "${gpu_args[@]}" \
  --shm-size="$SHM_SIZE" \
  "${env_args[@]}" \
  -v "$LOCAL_NIM_CACHE:/opt/nim/.cache" \
  -u "$(id -u)" \
  -p "$HOST_PORT:8000" \
  "$IMAGE"

cat <<EOF

Started $CONTAINER_NAME.

Watch startup:
  docker logs -f $CONTAINER_NAME

Check readiness:
  curl -fsS http://localhost:$HOST_PORT/v1/health/ready

List served models:
  curl -s http://localhost:$HOST_PORT/v1/models
EOF
