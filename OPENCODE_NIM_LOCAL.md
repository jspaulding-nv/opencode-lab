# OpenCode with Local Nemotron 3 Super NIM

This config points OpenCode at the local OpenAI-compatible NIM endpoint:

```bash
http://127.0.0.1:8000/v1
```

The served model ID should be:

```bash
nvidia/nemotron-3-super-120b-a12b
```

## 1. Verify NIM

On the H100 host:

```bash
curl -fsS http://127.0.0.1:8000/v1/health/ready
curl -s http://127.0.0.1:8000/v1/models
```

If OpenCode shows an error like `"auto" tool choice requires --enable-auto-tool-choice and --tool-call-parser to be set`, or if OpenCode shows internal thinking text such as `</think>`, set this value in `.env.super`:

```bash
NIM_PASSTHROUGH_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder --default-chat-template-kwargs '{\"enable_thinking\":false}'"
```

Then restart NIM:

```bash
RECREATE=1 ./deploy-nemotron3-super-nim.sh
```

Then test tool calling directly:

```bash
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "nvidia/nemotron-3-super-120b-a12b",
    "messages": [{"role": "user", "content": "What files are in this project? Use the tool."}],
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

The response should include `tool_calls` rather than the server-side `auto tool choice` error.

## 2. Use Project-Local Config

Copy `opencode-nim-local.json` into your project as `opencode.json`:

```bash
cp opencode-nim-local.json /path/to/your/project/opencode.json
cd /path/to/your/project
opencode
```

Inside OpenCode, run:

```text
/models
```

Then select:

```text
NVIDIA NIM Local / Nemotron 3 Super 120B A12B (local NIM)
```

## 3. Use Global Config

If you want this available everywhere:

```bash
mkdir -p ~/.config/opencode
cp opencode-nim-local.json ~/.config/opencode/opencode.json
opencode
```

If you already have a global OpenCode config, merge the `provider`, `model`, `small_model`, and `agent` sections instead of replacing the file.

## Notes

The config uses `@ai-sdk/openai-compatible` because NIM exposes `/v1/chat/completions`.

The model limit is set to `32768` context tokens to match the current NIM deployment's `NIM_MAX_MODEL_LEN=32768`. The output limit is set conservatively to `8192`.

The NIM deployment sets `--default-chat-template-kwargs '{"enable_thinking":false}'`, and the OpenCode model config also sets `options.chat_template_kwargs.enable_thinking=false`. Without this, Nemotron can expose internal thinking text such as `</think>` in the TUI.

The dummy `apiKey` is intentional. The local NIM endpoint does not need one, but the OpenAI-compatible client stack often expects a non-empty API key field.
