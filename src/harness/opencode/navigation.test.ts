import { expect, test } from "bun:test";

const source = process.env.OPENCODE_SOURCE;
const helper = process.env.KONDUCTOR_NAVIGATION_HELPER;
// OpenCode's general test preload clears tmux state to protect the user's panes.
const isolated = process.env.KONDUCTOR_TEST_TMUX;
if (!isolated?.startsWith("/tmp/opencode/navigation-acceptance-")) {
  throw new Error("Navigation acceptance requires its own isolated tmux server");
}
process.env.TMUX = isolated;
process.env.TMUX_PANE = process.env.KONDUCTOR_TEST_PANE;
if (!source || !helper || !process.env.TMUX_PANE) {
  throw new Error(
    "Run navigation.test.ts in an isolated tmux pane with OPENCODE_SOURCE and KONDUCTOR_NAVIGATION_HELPER"
  );
}
const { createAppFixture } = await import(`${source}/packages/tui/test/fixture/app.ts`);
const { directory, json } = await import(`${source}/packages/tui/test/fixture/tui-client.ts`);
const { tmpdir } = await import(`${source}/packages/tui/test/fixture/fixture.ts`);
const pane = process.env.TMUX_PANE;

async function command(...args: string[]) {
  const child = Bun.spawn(args, { stdout: "pipe", stderr: "pipe" });
  const [code, stdout, stderr] = await Promise.all([
    child.exited,
    new Response(child.stdout).text(),
    new Response(child.stderr).text(),
  ]);
  return { code, stdout: stdout.trim(), stderr: stderr.trim() };
}

async function wait(predicate: () => Promise<boolean>) {
  const deadline = Date.now() + 3000;
  while (!(await predicate())) {
    if (Date.now() >= deadline) {
      throw new Error("Navigation integration condition did not become true");
    }
    await Bun.sleep(10);
  }
}

test.each([false, true])("production plugin uses client-local tmux, enabled: %s", async (enabled) => {
  await using plugin = await tmpdir();
  const entry = `${plugin.path}/tui.ts`;
  const original = await Bun.file(`${import.meta.dir}/navigation/tui.ts`).text();
  await Bun.write(entry, original);
  await Bun.write(`${plugin.path}/package.json`, await Bun.file(`${import.meta.dir}/navigation/package.json`).text());
  const session = {
    id: "ses_outer_navigation",
    title: "Outer navigation",
    projectID: "project",
    location: { directory },
    cost: 0,
    tokens: { input: 0, output: 0, reasoning: 0, cache: { read: 0, write: 0 } },
    time: { created: 0, updated: 0 },
  };
  {
    await using app = await createAppFixture({
      config: {
        animations: false,
        tabs: { mode: "off" },
        experimental: { "vim-pane-navigation": enabled },
        plugins: [{ package: plugin.path, options: { helper } }],
      },
      args: { sessionID: session.id },
      fetch(url: URL) {
        if (url.pathname === "/api/session") {
          return json({ data: [session], cursor: {} });
        }
        if (url.pathname === `/api/session/${session.id}`) {
          return json({ data: session });
        }
        if (url.pathname === `/api/session/${session.id}/message`) {
          return json({ data: [], cursor: {} });
        }
        if (url.pathname === `/api/session/${session.id}/inbox`) {
          return json({ data: [] });
        }
        if (url.pathname === `/api/session/${session.id}/permission`) {
          return json({ data: [] });
        }
      },
    });
    await app.ready;
    await app.waitForFrame(() => Boolean(app.renderer.currentFocusedEditor));
    await wait(
      async () => (await command("tmux", "display-message", "-p", "-t", pane, "#{@konductor_navigation}")).stdout !== ""
    );
    const admission = await command(helper, "admitted", pane);
    if (admission.code !== (enabled ? 0 : 3)) {
      console.log(
        "foreground",
        Bun.spawnSync([helper, "foreground", String(process.pid)], { stdin: "inherit" }).stdout.toString()
      );
      console.log("claim", await command("tmux", "display-message", "-p", "-t", pane, "#{@konductor_navigation}"));
      console.log("process", await command("ps", "-o", "pid,pgid,tpgid,tty", "-p", String(process.pid)));
    }
    expect(admission.code).toBe(enabled ? 0 : 3);
    const beforeReload = await command("tmux", "display-message", "-p", "-t", pane, "#{@konductor_navigation}");
    await Bun.write(
      entry,
      original.replace('id: "konductor.pane-navigation"', 'id: "konductor.pane-navigation-reloaded"')
    );
    await wait(async () => {
      const current = await command("tmux", "display-message", "-p", "-t", pane, "#{@konductor_navigation}");
      return current.stdout !== "" && current.stdout !== beforeReload.stdout;
    });
    expect((await command(helper, "admitted", pane)).code).toBe(enabled ? 0 : 3);
    if (enabled) {
      app.mockInput.pressKey("h", { ctrl: true });
      await wait(
        async () => (await command("tmux", "display-message", "-p", "-t", pane, "#{pane_active}")).stdout === "0"
      );
      expect((await command("tmux", "select-pane", "-t", pane)).code).toBe(0);
      app.mockInput.pressKey("l", { ctrl: true });
      await app.waitForVisualIdle();
      expect((await command("tmux", "display-message", "-p", "-t", pane, "#{pane_active}")).stdout).toBe("1");
    }
  }
  await wait(
    async () => (await command("tmux", "display-message", "-p", "-t", pane, "#{@konductor_navigation}")).stdout === ""
  );
});
