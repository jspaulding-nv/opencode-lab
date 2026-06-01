# Participant Guide: OpenCode with Local Nemotron 3 Super

Welcome. In this lab, you will use OpenCode inside the LaunchPad **VS Code Environment**. Staff have already deployed a local NVIDIA Nemotron 3 Super NIM model on the machine.

You do not need to install Docker, configure GPUs, or provide an NGC key.

## NVIDIA LaunchPad Environment

NVIDIA LaunchPad provides a ready-to-use GPU development environment with common tools, resources, and IDE extensions already configured.

This deployment includes:

- NVIDIA Cloud Native Stack with Docker
- Code Server with a prepared workspace
- Full `sudo` privileges on the GPU node
- Optional SSH access for direct hardware access

You will use the **Code Server IDE** for this lab. LaunchPad also provides a browser desktop environment, WebSSH, and Jupyter Notebook if you need them.

## Local Nemotron 3 Super Model

This lab uses **NVIDIA Nemotron 3 Super 120B A12B FP8** through a local NVIDIA NIM endpoint. It is a 120B-parameter, 12B-active model designed for agentic workflows, tool use, RAG, and long-context reasoning.

In this lab, staff have already deployed the model locally on the LaunchPad GPU node and configured OpenCode to use it.

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

You can maximize the terminal by clicking the up arrow icon on the right side of the terminal panel.

![VS Code terminal maximize icon](images/launchpad3.png)

## 2. Check the Local Model

```bash
curl -fsS http://127.0.0.1:8000/v1/health/ready
curl -s http://127.0.0.1:8000/v1/models | jq .
```

Expected model:

```text
nvidia/nemotron-3-super-120b-a12b
```

### If NIM Is Not Yet Deployed

Staff normally deploys NIM before the lab starts. If the readiness check fails and staff asks you to deploy it yourself, make sure staff has already prepared `.env.super`, then go to the lab repo and start the container:

```bash
cd ~/opencode-lab
./deploy-nemotron3-super-nim.sh
```

If replacing a previous run:

```bash
RECREATE=1 ./deploy-nemotron3-super-nim.sh
```

You should see the terminal pull the image from NGC and then print output similar to:

```text
Starting nemotron3-super-nim on host port 8000...
Using NIM_MODEL_PROFILE=57d42cc7d33914933427e7f8d8cb1773bc11e5c96826c92095820a8776e6a4f6, NIM_MAX_MODEL_LEN=32768
ff4b1cc5cf3335cd30dec687a7b230fe52f6e581443c9fdf8576facb14b09f33

Started nemotron3-super-nim.
```

Watch startup:

```bash
docker logs -f nemotron3-super-nim
```

Press `Control-C` when you are done watching the logs.

Startup can take several minutes while NIM downloads and prepares model artifacts.

Look for these lines in the Docker logs:

```text
(APIServer pid=77) INFO:     Waiting for application startup.
(APIServer pid=77) INFO:     Application startup complete.
```

Check readiness from the terminal again:

```bash
curl -fsS http://127.0.0.1:8000/v1/health/ready
curl -s http://127.0.0.1:8000/v1/models | jq .
```

## 3. Start OpenCode

Go to your Documents workspace:

```bash
cd ~/Documents
```

Start OpenCode:

```bash
opencode
```

OpenCode should default to **Nemotron 3 Super 120B A12B (local NIM)** as shown:

![OpenCode showing the local Nemotron 3 Super model selected](images/opencode1.png)

If it does not, you can select the model inside OpenCode:

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
Create a simple Hello World program in Python. Keep your response short: tell me the file you created and how to run it with python3.
```

## 5. Planning Mode

For the next prompt, press `Tab` to switch into **Plan** mode. Plan mode is indicated by the orange line and orange text.

Paste this prompt:

```text
I want to build a simple, fun web-based To-Do list app with neon colors. It should let me add tasks, delete them, and play a 'ding' sound when I complete one.
```

In Planning mode, OpenCode may ask follow-up questions like the app scope, storage behavior, sound effect, or whether to proceed. Use the arrow keys to choose an option and press `Enter` to confirm. If offered, you can also type your own answer.

## 6. Test the App

Press `Tab` to switch back into **Build** mode.

Paste this prompt:

```text
Run the app on port 8001.
```

OpenCode will run the server for about 2 minutes to test it.

You may see a notification in the bottom-right corner of VS Code that your app is running on port `8001`. Click the green **Open in Browser** button.

![VS Code port notification for port 8001](images/launchpad4.png)

If you missed the notification, open the **Ports** tab next to the **Terminal** tab. Look for the line for port `8001`. Under **Forwarded Addresses**, hover over the address and click the globe icon to open the app in your browser.

![VS Code Ports tab showing the forwarded port globe icon](images/launchpad5.png)

You can also create another terminal and run the Python server yourself:

```bash
python3 -m http.server 8001
```

## 7. Keep Experimenting

Now try modifying the app. Stay in **Build** mode and ask OpenCode for small changes, then run the app again.

Example prompts:

```text
Change the background to a neon sunset gradient.
```

```text
Make the font bigger and easier to read.
```

```text
Add a fun animation when I complete a task.
```

If you test the UI in a browser, style changes may be cached. If your latest changes do not show up, ask OpenCode to include a cache buster.

```text
Add a cache buster so the browser loads the latest CSS and JavaScript.
```

## 8. Advanced Exercise

If you finish early, turn the To-Do list into a more complete app. Try these prompts one at a time, testing after each change:

```text
Add localStorage so tasks stay saved after I refresh the page.
```

```text
Add filters for All, Active, and Completed tasks.
```

```text
Add an edit button so I can rename a task.
```

```text
Add keyboard support: Enter adds a task and Escape cancels editing.
```

```text
Make the app responsive and polished on mobile.
```

Ask OpenCode to review before making the next change:

```text
Review the code and suggest three improvements before changing anything.
```

Then ask OpenCode to explain what it built:

```text
Explain the main files in this app and how the UI state works. Keep it beginner friendly.
```

When you are done, quit OpenCode with:

```text
/exit
```

## 9. Quick Troubleshooting

If OpenCode does not respond, ask staff to check that the NIM container is running:

```bash
docker ps --filter name=nemotron3-super-nim
```

If you see an error about `tool_choice` or tool calls, ask staff to restart NIM with tool calling enabled.

If OpenCode shows internal thinking text such as `</think>`, ask staff to refresh the OpenCode local NIM config.

We will refine this participant guide before the lab.
