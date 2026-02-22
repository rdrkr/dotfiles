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
interface Task {
  title: string;
  command: string;
  args: string[];
  cwd?: string;
  shell?: boolean;
}

/**
 * Task group definition
 */
interface TaskGroup {
  title: string;
  tasks: Task[];
}

/**
 * List of task groups to run
 */
const taskGroups: TaskGroup[] = [
  {
    title: "Updating Homebrew",
    tasks: [
      {
        title: "Updating Homebrew packages",
        command: "brew",
        args: ["update"],
      },
      {
        title: "Upgrading Homebrew packages",
        command: "brew",
        args: ["upgrade"],
      },
      {
        title: "Cleaning up Homebrew packages",
        command: "brew",
        args: ["cleanup", "--prune=all"],
      },
      {
        title: "Upgrading App Store apps",
        command: "mas",
        args: ["upgrade"],
      },
    ],
  },
  {
    title: "Global NPM packages",
    tasks: [
      {
        title: "Upgrading Global NPM packages",
        command: "npm",
        args: ["upgrade", "--global"],
      },
    ],
  },
  {
    title: "Pipx packages",
    tasks: [
      {
        title: "Upgrading Pipx packages",
        command: "pipx",
        args: ["upgrade-all"],
      },
    ],
  },
  {
    title: "Zinit",
    tasks: [
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
    ],
  },
  {
    title: "LazyVim",
    tasks: [
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
    ],
  },
  {
    title: "Pre-commit hooks",
    tasks: [
      {
        title: "Updating pre-commit hooks",
        command: "pre-commit",
        args: ["autoupdate"],
        cwd: join(HOME, "dotfiles"),
      },
    ],
  },
]

// Run all groups in parallel, where each group runs its tasks sequentially with live output streaming
await task.group(
  (group) => taskGroups.map(({ title, tasks }) =>
    group(
      title,
      async ({ task }) => await task.group(
        (task) => tasks.map(({ title, command, args, cwd }) =>
          task(
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
                    setTitle(title);
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
                })
              })
            },
          ),
        ),
        { 
          concurrency: 1, 
          maxVisible: 10,
          stopOnError: true 
        },
        ),
      ),
    ),
  { 
    concurrency: taskGroups.length, 
    maxVisible: 10,
    stopOnError: false 
  },
)
