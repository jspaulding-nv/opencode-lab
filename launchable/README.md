# Brev Launchable: VS Code Server + OpenCode

This is a NVIDIA Brev Launchable for a browser-based VS Code Server development environment with OpenCode installed.

It gives users a ready-to-use coding workspace in the browser, with OpenCode available from the integrated terminal:

```bash
opencode
```

OpenCode is an AI coding agent that runs in the terminal. It can inspect a repository, edit files, run commands, and help users build, debug, and iterate on code from inside the workspace.

VS Code Server runs through code-server, so users can edit files, open terminals, run local apps, and work with the repository directly from the Brev environment.

By default, VS Code Server is exposed on port `8080`.

OpenCode is installed for the VM user and added to the shell `PATH`, so it is available in new terminals inside VS Code Server.
