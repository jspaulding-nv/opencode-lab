# Staff Setup: NVIDIA LaunchPad + Nemotron 3 Super NIM + OpenCode

This guide is for staff preparing an NVIDIA LaunchPad lab environment. It assumes the machine has two H100 GPUs, Docker is already installed, and you are already inside the **VS Code Environment**.

In LaunchPad, participants or staff reach this environment by logging in, opening the **Resources** menu, and selecting **Code Server IDE**.

The objective is to deploy NVIDIA Nemotron 3 Super 120B A12B as a local NIM service and configure OpenCode so lab participants can use the local model from VS Code Server.

## What Staff Will Set Up

- Nemotron 3 Super NIM in Docker
- Local OpenAI-compatible endpoint at `http://127.0.0.1:8000/v1`
- FP8 tensor-parallel profile for two H100 GPUs
- OpenCode installed in the VS Code Server environment
- OpenCode config pointed at the local NIM endpoint
- Basic validation and benchmark commands
- Teardown commands for retesting the lab setup

## Repository Files

This repository should include:

```text
deploy-nemotron3-super-nim.sh
.env.super.example
opencode-nim-local.json
SETUP.md
README.md
```

Do not commit `.env.super`; it contains the NGC API key.

## Prerequisites

LaunchPad is expected to provide:

- Ubuntu-based VS Code Server / Code Server IDE environment
- Two H100 GPUs
- NVIDIA driver
- Docker Engine
- NVIDIA Container Toolkit configured for Docker

Staff must provide:

- NVIDIA NGC account
- NGC Personal API Key with NGC Catalog access
- Accepted terms for the Nemotron 3 Super NIM container/model in NGC

## 1. Confirm the LaunchPad Host

After you enter the LaunchPad environment, open the **Resources** menu and select **Code Server IDE**.

![LaunchPad Resources menu with Code Server IDE selected](images/launchpad1.png)

In VS Code, create a new Bash terminal by going to **Terminal > New Terminal**.

![VS Code Terminal menu with New Terminal selected](images/launchpad2.png)

Run these commands in the VS Code Server terminal:

```bash
nvidia-smi -L
docker --version
docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi
```

Expected GPU output should show two H100 GPUs, for example:

```text
GPU 0: NVIDIA H100 NVL
GPU 1: NVIDIA H100 NVL
```

If Docker cannot see the GPUs, stop and fix the LaunchPad environment before continuing. This lab guide assumes Docker and NVIDIA Container Toolkit are already installed.

NIM for LLMs does not support MIG mode. If MIG is enabled, disable it before the lab.

## 2. Prepare the Repo

Clone this repo into the VS Code Server environment:

```bash
git clone https://github.com/jspaulding-nv/opencode-lab.git
cd opencode-lab
chmod +x deploy-nemotron3-super-nim.sh
```

Install small CLI utilities if missing:

```bash
sudo apt-get update
sudo apt-get install -y curl jq git ca-certificates
```

## 3. Configure NIM

Create a local env file:

```bash
cp .env.super.example .env.super
chmod 600 .env.super
```

Edit it:

```bash
nano .env.super
```

Set:

```bash
NGC_API_KEY=paste_your_ngc_api_key_here
```

`LOCAL_NIM_CACHE` is already set to `/data/nim-cache/nemotron-3-super-120b-a12b` in `.env.super.example` and in the deploy script default. The deploy script creates the cache directory automatically. If `/data` requires elevated permissions, the script will use `sudo` to create and chown the path.

Keep these recommended settings in `.env.super`:

```bash
IMAGE=nvcr.io/nim/nvidia/nemotron-3-super-120b-a12b@sha256:e24028cbc5bf3b3c1755ad37f898a0cd954845ab8c7012eb490aed4ac55b44ea
DOCKER_PLATFORM=linux/amd64
NIM_MODEL_PROFILE=57d42cc7d33914933427e7f8d8cb1773bc11e5c96826c92095820a8776e6a4f6
NIM_MAX_MODEL_LEN=32768
NIM_KVCACHE_PERCENT=0.9
NIM_PASSTHROUGH_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
NIM_PER_REQ_METRICS_ENABLE=1
```

The profile ID maps to `vllm-fp8-tp2-pp1-65.0`, which is compatible with two H100 80GB-class GPUs. `NIM_PASSTHROUGH_ARGS` is required because OpenCode sends OpenAI tool calls with `tool_choice: "auto"`.

## 4. Deploy Nemotron 3 Super NIM

Start the container:

```bash
./deploy-nemotron3-super-nim.sh
```

If replacing a previous run:

```bash
RECREATE=1 ./deploy-nemotron3-super-nim.sh
```

Watch startup:

```bash
docker logs -f nemotron3-super-nim
```

Startup can take a while while NIM downloads and prepares model artifacts.

Check readiness:

```bash
curl -fsS http://127.0.0.1:8000/v1/health/ready
curl -s http://127.0.0.1:8000/v1/models | jq .
```

Expected model ID:

```text
nvidia/nemotron-3-super-120b-a12b
```

## 5. Smoke Test NIM

```bash
MODEL="$(curl -s http://127.0.0.1:8000/v1/models | jq -r '.data[0].id')"

curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d "{
    \"model\": \"$MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Reply with one sentence confirming the lab model is ready.\"}],
    \"temperature\": 1.0,
    \"top_p\": 0.95,
    \"max_tokens\": 128,
    \"chat_template_kwargs\": {\"enable_thinking\": false}
  }" | jq .
```

Optional tool-call check:

```bash
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "nvidia/nemotron-3-super-120b-a12b",
    "messages": [{"role": "user", "content": "Use the tool to list files."}],
    "tools": [{
      "type": "function",
      "function": {
        "name": "list_files",
        "description": "List files in the current project.",
        "parameters": {
          "type": "object",
          "properties": {},
          "required": []
        }
      }
    }],
    "tool_choice": "auto",
    "max_tokens": 256
  }' | jq .
```

The response should include `tool_calls`, not a server error about `tool_choice`.

## 6. Install OpenCode

If OpenCode is already installed:

```bash
opencode --version
```

If it is not installed:

```bash
curl -fsSL https://opencode.ai/install | bash
export PATH="$HOME/.opencode/bin:$PATH"
opencode --version
```

Alternative with npm:

```bash
npm install -g opencode-ai
opencode --version
```

## 7. Configure OpenCode for Local NIM

For the current user in this VS Code Server environment:

```bash
mkdir -p ~/.config/opencode
cp opencode-nim-local.json ~/.config/opencode/opencode.json
```

Confirm the config:

```bash
cat ~/.config/opencode/opencode.json
```

It should point to:

```text
http://127.0.0.1:8000/v1
```

and select:

```text
nim-local/nvidia/nemotron-3-super-120b-a12b
```

Validate OpenCode non-interactively:

```bash
opencode run "Reply with exactly: local Nemotron ready"
```

Start the TUI:

```bash
opencode
```

Inside OpenCode:

```text
/models
```

Select:

```text
NVIDIA NIM Local / Nemotron 3 Super 120B A12B (local NIM)
```

## 8. Participant Handoff

Before participants start:

```bash
docker ps --filter name=nemotron3-super-nim
curl -fsS http://127.0.0.1:8000/v1/health/ready
opencode --version
```

Point participants to [README.md](./README.md).

For multi-participant labs, give each participant a separate UNIX user or at least a separate project directory. The NIM service can be shared on `localhost:8000`, but OpenCode's file-editing tools operate in the participant's current workspace.

## Troubleshooting

### NIM Pull Fails With `Incorrect Repository Format`

Use the digest-based image from `.env.super`:

```bash
docker pull --platform linux/amd64 \
  nvcr.io/nim/nvidia/nemotron-3-super-120b-a12b@sha256:e24028cbc5bf3b3c1755ad37f898a0cd954845ab8c7012eb490aed4ac55b44ea
```

### OpenCode Shows No Feedback or Tool Choice Error

If OpenCode shows:

```text
"auto" tool choice requires --enable-auto-tool-choice and --tool-call-parser to be set
```

make sure `.env.super` contains:

```bash
NIM_PASSTHROUGH_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder"
```

Then restart:

```bash
RECREATE=1 ./deploy-nemotron3-super-nim.sh
```

### Model Profile Is Rejected

List compatible profiles:

```bash
LIST_PROFILES=1 ./deploy-nemotron3-super-nim.sh
```

For two H100 80GB-class GPUs, look for:

```text
vllm-fp8-tp2-pp1-65.0
```

The matching profile ID is:

```text
57d42cc7d33914933427e7f8d8cb1773bc11e5c96826c92095820a8776e6a4f6
```

### Port 8000 Is Already In Use

Change `HOST_PORT` in `.env.super`, for example:

```bash
HOST_PORT=8001
```

Then update `opencode-nim-local.json`:

```json
"baseURL": "http://127.0.0.1:8001/v1"
```

Restart NIM and OpenCode.

## Teardown

Use this section to reset the LaunchPad environment after testing.

### Stop and Remove the NIM Container

```bash
docker rm -f nemotron3-super-nim
```

Verify:

```bash
docker ps -a | grep nemotron3-super-nim || true
curl -fsS http://127.0.0.1:8000/v1/health/ready || true
```

### Remove the NIM Image

This frees Docker image space but keeps downloaded model cache files:

```bash
docker rmi nvcr.io/nim/nvidia/nemotron-3-super-120b-a12b@sha256:e24028cbc5bf3b3c1755ad37f898a0cd954845ab8c7012eb490aed4ac55b44ea
```

If Docker reports the image is in use:

```bash
docker ps -a
docker rm <container-id-or-name>
```

### Remove the NIM Model Cache

This deletes large downloaded model artifacts:

```bash
rm -rf /data/nim-cache/nemotron-3-super-120b-a12b
rm -rf ~/.cache/nim/nemotron-3-super-120b-a12b
```

### Remove Lab Secrets and NGC Docker Login

```bash
rm -f .env.super .env.super.bak
docker logout nvcr.io
```

Do not remove `~/.docker/config.json` unless this machine has no other Docker registry logins you care about.

### Uninstall OpenCode

If installed with the official install script:

```bash
rm -rf ~/.opencode
```

For the LaunchPad `nvidia` user, remove the default OpenCode block from `.bashrc`:

```bash
cp ~/.bashrc ~/.bashrc.before-opencode-teardown
sed -i '/^# opencode$/,+1d' ~/.bashrc
```

This removes:

```bash
# opencode
export PATH=/home/nvidia/.opencode/bin:$PATH
```

Clear the current shell's cached command path and remove the old OpenCode bin directory from the current `PATH`:

```bash
hash -r
NEW_PATH=""
IFS=':' read -ra PATH_PARTS <<< "$PATH"
for PATH_PART in "${PATH_PARTS[@]}"; do
  [ "$PATH_PART" = "$HOME/.opencode/bin" ] && continue
  [ -n "$NEW_PATH" ] && NEW_PATH="$NEW_PATH:"
  NEW_PATH="$NEW_PATH$PATH_PART"
done
export PATH="$NEW_PATH"
unset NEW_PATH PATH_PARTS PATH_PART
hash -r
```

If OpenCode was installed under a different user or shell, remove the equivalent OpenCode PATH block from that user's shell config.

If installed with npm:

```bash
npm uninstall -g opencode-ai
```

Remove OpenCode config and local auth/session data:

```bash
rm -rf ~/.config/opencode
rm -rf ~/.local/share/opencode
rm -rf ~/.cache/opencode
```

Verify uninstall:

```bash
hash -r
command -v opencode || echo "opencode removed"
```

## References

- [NVIDIA NIM for LLMs: Tool Calling and MCP Integration](https://docs.nvidia.com/nim/large-language-models/latest/advanced-use-cases/tool-calling-and-mcp.html)
- [NVIDIA NIM for LLMs: Certified NIM Support Matrix](https://docs.nvidia.com/nim/large-language-models/latest/reference/support-matrix.html)
- [Docker GPU support](https://docs.docker.com/engine/containers/gpu/)
- [OpenCode docs](https://opencode.ai/docs/)
- [OpenCode providers](https://opencode.ai/docs/providers)
- [OpenCode config](https://opencode.ai/docs/config)
