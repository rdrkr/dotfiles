/**
 * Copyright (c) 2026, Ronen Druker. All rights reserved.
 */

import { spawn } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";
import task from "tasuku";

const HOME = homedir();
const ZINIT_HOME =
  process.env.ZINIT_HOME ?? join(HOME, ".local/share/zinit/zinit.git");

/**
 * Task definition
 */
interface TaskDef {
  title: string;
  command: string;
  args: string[];
  cwd?: string;
  shell?: boolean;
}

/**
 * List of tasks to run
 */
const tasks: TaskDef[] = [
  {
    title: "Updating Homebrew",
    command: "brew",
    args: ["update"],
  },
  {
    title: "Upgrading Homebrew packages",
    command: "brew",
    args: ["upgrade"],
  },
  {
    title: "Cleaning up Homebrew",
    command: "brew",
    args: ["cleanup", "--prune=all"],
  },
  {
    title: "Upgrading App Store apps",
    command: "mas",
    args: ["upgrade"],
  },
  {
    title: "Upgrading Global NPM packages",
    command: "npm",
    args: ["upgrade", "--global"],
  },
  {
    title: "Upgrading Pipx packages",
    command: "pipx",
    args: ["upgrade-all"],
  },
  {
    title: "Updating Zinit",
    command: "zsh",
    args: [
      "-l",
      "-c",
      `source "${ZINIT_HOME}/zinit.zsh" && zinit self-update`,
    ],
  },
  {
    title: "Updating Zinit plugins",
    command: "zsh",
    args: [
      "-l",
      "-c",
      `source "${ZINIT_HOME}/zinit.zsh" && zinit update --quiet --all`,
    ],
  },
  {
    title: "Clearing Zinit cache",
    command: "zsh",
    args: [
      "-l",
      "-c",
      `source "${ZINIT_HOME}/zinit.zsh" && zinit cclear`,
    ],
  },
  {
    title: "Syncing LazyVim",
    command: "nvim",
    args: ["--headless", "+Lazy! sync", "+qa"],
  },
  {
    title: "Updating LazyVim",
    command: "nvim",
    args: ["--headless", "+Lazy! update", "+qa"],
  },
  {
    title: "Updating Mason",
    command: "nvim",
    args: ["--headless", "+MasonUpdate", "+qa"],
  },
  {
    title: "Updating Treesitter",
    command: "nvim",
    args: ["--headless", "+TSUpdate", "+qa"],
  },
  {
    title: "Updating pre-commit hooks",
    command: "pre-commit",
    args: ["autoupdate"],
    cwd: join(HOME, "dotfiles"),
  },
];

// Run all tasks sequentially with live output streaming
await task.group(
  (t) =>
    tasks.map(({ title, command, args, cwd }) =>
      t(
        title,
        async ({ setTitle, setError, streamPreview }) => {
          await new Promise<void>((resolve, reject) => {
            const child = spawn(command, args, {
              cwd,
              env: { ...process.env, TERM: "dumb" },
              stdio: ["ignore", "pipe", "pipe"],
            });

            child.stdout.pipe(streamPreview, { end: false });
            child.stderr.pipe(streamPreview, { end: false });

            child.on("close", (code) => {
              if (code === 0) {
                setTitle(`${title} ✓`);
                resolve();
              } else {
                const msg = `exited with code ${code}`;
                setError(msg);
                reject(new Error(msg));
              }
            });

            child.on("error", (err) => {
              setError(err.message);
              reject(err);
            });
          });
        },
      ),
    ),
  { concurrency: 1, stopOnError: false },
);
