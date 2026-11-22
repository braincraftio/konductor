import { Plugin } from "@opencode/plugin/tui";
import { mkdtemp, rm } from "node:fs/promises";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";

export default Plugin.define({
  id: "konductor.pane-navigation",
  async setup(context) {
    const helper = context.options.helper;
    if (typeof helper !== "string" || !helper.startsWith("/")) {
      throw new Error("Konductor navigation requires an absolute helper executable");
    }
    const invoke = (...args: string[]) => {
      const result = Bun.spawnSync([helper, ...args], {
        stdin: "inherit",
        stdout: "pipe",
        stderr: "pipe",
        timeout: 2500,
        maxBuffer: 8192,
      });
      if (result.exitCode === 3) {
        return undefined;
      }
      if (!result.success) {
        throw new Error(result.stderr.toString().trim() || "Navigation helper failed");
      }
      return result.stdout.toString().trim();
    };
    const pane = invoke("parent");
    if (!pane) {
      return;
    }

    const directory = await mkdtemp(join(tmpdir(), "k9-nav-"));
    const socket = join(directory, "control");
    const server = createServer((connection) => {
      connection.on("error", (error) => {
        context.ui.toast.show({ message: error.message, variant: "error" });
      });
      connection.setTimeout(250, () => connection.destroy());
      const enabled = context.keymap.commands().some((command) => {
        if (command.id !== "pane.navigate.left") {
          return false;
        }
        return typeof command.enabled === "function" ? command.enabled() : command.enabled !== false;
      });
      try {
        const tty = invoke("foreground", String(process.pid));
        connection.end(`${JSON.stringify({ pid: process.pid, enabled: enabled && Boolean(tty), tty })}\n`);
      } catch (error) {
        connection.destroy();
        context.ui.toast.show({ message: String(error), variant: "error" });
      }
    });
    const cleanup = async () => {
      server.close();
      try {
        invoke("unregister", pane, String(process.pid), socket);
      } finally {
        await rm(directory, { recursive: true, force: true });
      }
    };
    try {
      await new Promise<void>((resolve, reject) => {
        server.once("error", reject);
        server.listen(socket, () => {
          server.off("error", reject);
          resolve();
        });
      });
      server.on("error", (error) => {
        context.ui.toast.show({ message: error.message, variant: "error" });
      });
      invoke("register", pane, String(process.pid), socket);
      context.keymap.layer(() => ({
        mode: "global",
        commands: ["left", "down", "up", "right", "previous"].map((direction) => ({
          id: `pane.boundary.${direction}`,
          run: () => {
            try {
              if (invoke("move", direction, pane) === undefined) {
                return false;
              }
            } catch (error) {
              context.ui.toast.show({ message: String(error), variant: "error" });
            }
          },
        })),
      }));
    } catch (error) {
      await cleanup();
      throw error;
    }
    return cleanup;
  },
});
