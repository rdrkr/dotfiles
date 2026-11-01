/**
 * Copyright (c) 2026, Ronen Druker. All rights reserved.
 */

import { spawn } from "node:child_process"
import { accessSync, constants, readFileSync, statSync } from "node:fs"
import { homedir } from "node:os"
import { delimiter, join, resolve } from "node:path"
import { parse } from "yaml"
import { GroupView, Renderer, TaskView } from "./renderer.ts"

/**
 * Task definition
 */
interface Task {
  /** Title shown while the task runs */
  title: string
  /** Executable to spawn; ~ and environment variables are expanded */
  command: string
  /** Arguments, passed verbatim except for a leading ~ (shell scripts are left to their shell) */
  args: string[]
  /** Working directory; ~ and environment variables are expanded */
  cwd?: string
  /** Keep the task's output visible after it succeeds */
  verbose?: boolean
  /** Executables that must be on PATH or the task is skipped; defaults to the command itself */
  requires?: string | string[]
}

/**
 * Task group definition
 */
interface TaskGroup {
  /** Title shown above the group's tasks */
  title: string
  /** Stage the group runs in; every group of a lower stage finishes first (default 0) */
  stage?: number
  /** Tasks run one after another */
  tasks: Task[]
}

/**
 * YAML task file schema
 */
interface TaskFile {
  /** Task file name */
  name: string
  /** Description shown by --help */
  description: string
  /** Usage line shown by --help */
  usage: string
  /** Groups run in parallel within their stage */
  groups: TaskGroup[]
}

// CLI arguments
const argv = process.argv.slice(2)
const flags = argv.filter((a) => a.startsWith("-"))
const positional = argv.filter((a) => !a.startsWith("-"))

const verbose = flags.includes("--verbose") || flags.includes("-v")
const help = flags.includes("--help") || flags.includes("-h")

if (!help && positional.length === 0) {
  console.error("Error: YAML task file is required\n")
  console.error("Usage: run-tasks <file.yaml> [options]")
  console.error("       run-tasks --help for more information")
  process.exit(1)
}

// Load and parse YAML
const yamlPath = resolve(positional[0] ?? "")
let taskFile: TaskFile

try {
  taskFile = parse(readFileSync(yamlPath, "utf-8")) as TaskFile
} catch (err) {
  if (help) {
    console.log(`Usage: run-tasks <file.yaml> [options]

Options:
  --verbose, -v  Show stdout output for each task (stderr is always shown)
  --help, -h     Show this help message`)
    process.exit(0)
  }
  console.error(`Error: Could not read task file: ${yamlPath}`)
  console.error((err as Error).message)
  process.exit(1)
}

if (help) {
  console.log(`${taskFile.description}

Usage: ${taskFile.usage}

Options:
  --verbose, -v  Show stdout output for each task (stderr is always shown)
  --help, -h     Show this help message`)
  process.exit(0)
}

/**
 * Expand a leading ~ (alone or followed by a path separator) to the home directory
 */
function expandTilde(str: string): string {
  return str.replace(/^~(?=$|[\\/])/, homedir())
}

/**
 * Expand environment variables ($VAR, ${VAR:-default}) and a leading ~ in a string
 */
function expandVars(str: string): string {
  return expandTilde(str)
    .replace(/\$\{([A-Z_][A-Z0-9_]*):-([^}]*)\}/g, (_, name, fallback) =>
      process.env[name] ?? expandVars(fallback),
    )
    .replace(/\$([A-Z_][A-Z0-9_]*)/g, (_, name) => process.env[name] ?? "")
}

/**
 * Expand the command and cwd of a task; arguments only get a leading ~ expanded so that
 * scripts passed to `bash -c` / `zsh -c` reach their shell untouched
 */
function expandTask(t: Task): Task {
  return {
    title: t.title,
    command: expandVars(t.command),
    args: (t.args ?? []).map(expandTilde),
    ...(t.cwd && { cwd: expandVars(t.cwd) }),
    ...(t.verbose !== undefined && { verbose: t.verbose }),
    ...(t.requires !== undefined && { requires: t.requires }),
  }
}

/**
 * Whether a path is an executable regular file
 */
function isExecutableFile(path: string): boolean {
  try {
    if (!statSync(path).isFile()) {
      return false
    }
    accessSync(path, constants.X_OK)
    return true
  } catch {
    return false
  }
}

/**
 * Whether an executable can be found, either as a path or by name on PATH (honouring PATHEXT on Windows)
 */
function hasExecutable(name: string): boolean {
  const extensions =
    process.platform === "win32" ? ["", ...(process.env.PATHEXT ?? ".COM;.EXE;.BAT;.CMD").split(";")] : [""]
  const candidates = /[\\/]/.test(name)
    ? [resolve(name)]
    : (process.env.PATH ?? "")
        .split(delimiter)
        .filter(Boolean)
        .map((dir) => join(dir, name))

  return candidates.some((candidate) => extensions.some((ext) => isExecutableFile(candidate + ext)))
}

/**
 * Run a single task: skip it with a warning when a required executable is missing, otherwise
 * spawn its command and stream stdout/stderr into its view. Never rejects: a failure is
 * recorded on the view so the rest of the group still runs.
 */
async function runTask(t: Task, view: TaskView): Promise<void> {
  view.start()

  const missing = [t.requires ?? t.command].flat().filter((name) => !hasExecutable(name))
  if (missing.length > 0) {
    view.skip(`skipped, not found: ${missing.join(", ")}`)
    return
  }

  await new Promise<void>((resolve) => {
    const child = spawn(t.command, t.args, {
      cwd: t.cwd,
      env: { ...process.env, TERM: "dumb" },
      stdio: ["ignore", "pipe", "pipe"],
    })

    child.stdout.setEncoding("utf-8").on("data", (chunk: string) => view.append("stdout", chunk))
    child.stderr.setEncoding("utf-8").on("data", (chunk: string) => view.append("stderr", chunk))

    // a spawn failure can emit both "error" and "close": settle on whichever comes first
    child.on("close", (code, signal) => {
      if (view.status === "running") {
        if (code === 0) {
          view.succeed()
        } else {
          view.fail(code === null ? `killed by ${signal}` : `exited with code ${code}`)
        }
      }
      resolve()
    })

    child.on("error", (err) => {
      if (view.status === "running") {
        view.fail(err.message)
      }
      resolve()
    })
  })
}

/**
 * Run every group of one stage in parallel, where each group runs its tasks sequentially
 * with live output streaming; resolves to whether every task succeeded or was skipped
 */
async function runStage(renderer: Renderer, groups: Required<TaskGroup>[]): Promise<boolean> {
  const views = groups.map(
    (g) =>
      new GroupView(
        g.title,
        g.tasks.map((t) => {
          const isVerbose = verbose || Boolean(t.verbose)
          return new TaskView(t.title, isVerbose ? 100 : 10, isVerbose)
        }),
      ),
  )

  renderer.beginStage(views)
  try {
    await Promise.all(
      groups.map(async (group, i) => {
        const view = views[i]!
        view.start()
        // keep going after a failing task so the rest of the group's updates still run
        for (const [j, t] of group.tasks.entries()) {
          const taskView = view.tasks[j]!
          await runTask(t, taskView)
          renderer.taskFinished(view, taskView)
        }
        view.end()
      }),
    )
  } finally {
    renderer.endStage()
  }

  return views.every((g) => g.status !== "error")
}

const taskGroups = taskFile.groups.map((g) => ({
  title: g.title,
  stage: g.stage ?? 0,
  tasks: g.tasks.map(expandTask),
}))

// Stages run in ascending order so that, for example, package managers that replace other tools'
// binaries (Homebrew upgrading node, neovim or mise) finish before those tools update themselves
const stages = [...new Set(taskGroups.map((g) => g.stage))]
  .sort((a, b) => a - b)
  .map((stage) => taskGroups.filter((g) => g.stage === stage))

const renderer = new Renderer()

// Ctrl-C also reaches the tasks (they share the terminal's process group): leave the last
// frame on screen, restore the cursor and exit like a shell would
process.on("SIGINT", () => {
  renderer.abort()
  process.exit(130)
})

for (const groups of stages) {
  // every failure is already shown inline by its task; signal it through the exit code
  // and move on to the next stage
  if (!(await runStage(renderer, groups))) {
    process.exitCode = 1
  }
}
