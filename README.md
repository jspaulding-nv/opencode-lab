# Participant Guide: OpenCode with Local Nemotron 3 Super

Welcome. In this lab, you will use OpenCode inside the LaunchPad **VS Code Environment**. Staff have already deployed a local NVIDIA Nemotron 3 Super NIM model on the machine.

You do not need to install Docker, configure GPUs, or provide an NGC key.

## 1. Open the VS Code Environment

Staff will provide the LaunchPad URL for your lab environment. It will look like this:

```text
https://<uuid>.nvidialaunchpad.com/launch
```

1. Open the LaunchPad URL in your browser.
2. On the login page, sign in or sign up with your email address for an NVIDIA account.
3. After you enter the LaunchPad environment, open the **Resources** menu and select **Code Server IDE**.

![LaunchPad Resources menu with Code Server IDE selected](images/launchpad1.png)

4. In VS Code, create a new Bash terminal by going to **Terminal > New Terminal**.

![VS Code Terminal menu with New Terminal selected](images/launchpad2.png)

## 2. Check the Local Model

```bash
curl -fsS http://127.0.0.1:8000/v1/health/ready
curl -s http://127.0.0.1:8000/v1/models | jq .
```

Expected model:

```text
nvidia/nemotron-3-super-120b-a12b
```

## 3. Start OpenCode

Go to the lab project directory:

```bash
cd ~/opencode-lab
```

Start OpenCode:

```bash
opencode
```

Inside OpenCode, use:

```text
/models
```

Select:

```text
NVIDIA NIM Local / Nemotron 3 Super 120B A12B (local NIM)
```

## 4. First Prompt

Try:

```text
Inspect this project and tell me how it is organized. Do not make changes yet.
```

Use `Tab` to switch between Plan and Build modes.

## 5. Quick Troubleshooting

If OpenCode does not respond, ask staff to check that the NIM container is running:

```bash
docker ps --filter name=nemotron3-super-nim
```

If you see an error about `tool_choice` or tool calls, ask staff to restart NIM with tool calling enabled.

We will refine this participant guide before the lab.
