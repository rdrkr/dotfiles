/**
 * Copyright (c) 2026, Ronen Druker. All rights reserved.
 */

import { spawn } from "node:child_process"
import { readFileSync } from "node:fs"
import { homedir } from "node:os"
import { resolve } from "node:path"
import { parse } from "yaml"
import task from "tasuku"
// import task from 'tasuku/inline'          // inline renderer
// import task from 'tasuku/theme/claude'    // Claude Code theme
// import task from 'tasuku/theme/blink'     // reduced-motion theme
// import task from 'tasuku/theme/codex'     // OpenAI Codex theme

/**
 * Task definition
 */
interface Task {
  title: string
  command: string
  args: string[]
  cwd?: string
  verbose?: boolean
}

/**
 * Task group definition
 */
interface TaskGroup {
  title: string
  tasks: Task[]
}

/**
 * YAML task file schema
 */
interface TaskFile {
  name: string
  description: string
  usage: string
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
 * Expand environment variables ($VAR, ${VAR:-default}) and ~ in a string
 */
function expandVars(str: string): string {
  const home = homedir()
  return str
    .replace(/~/g, home)
    .replace(/\$\{([A-Z_][A-Z0-9_]*):-([^}]*)\}/g, (_, name, fallback) =>
      process.env[name] ?? expandVars(fallback),
    )
    .replace(/\$([A-Z_][A-Z0-9_]*)/g, (_, name) => process.env[name] ?? "")
}

/**
 * Expand vars in all string fields of a task
 */
function expandTask(t: Task): Task {
  return {
    title: t.title,
    command: expandVars(t.command),
    args: t.args.map(expandVars),
    ...(t.cwd && { cwd: expandVars(t.cwd) }),
    ...(t.verbose !== undefined && { verbose: t.verbose }),
  }
}

const taskGroups = taskFile.groups.map((g) => ({
  title: g.title,
  tasks: g.tasks.map(expandTask),
}))

// Run all groups in parallel, where each group runs its tasks sequentially with live output streaming
await task.group(
  (rootCreator) => taskGroups.map(({ title, tasks }) =>
    rootCreator(
      title,
      async () => await task.group(
        (childCreator) => tasks.map(({ title, command, args, cwd, verbose: taskVerbose }) => {
          const isVerbose = verbose || taskVerbose;
          const registeredTask = childCreator(
            "Waiting...",
            async ({ setTitle, setError, streamPreview }) => {
              setTitle(title)

              await new Promise<void>((resolve, reject) => {
                const child = spawn(command, args, {
                  cwd,
                  env: { ...process.env, TERM: "dumb" },
                  stdio: ["ignore", "pipe", "pipe"],
                })

                child.stdout.pipe(streamPreview, { end: false })
                child.stderr.pipe(streamPreview, { end: false })

                child.on("close", (code) => {
                  if (code === 0) {
                    setTitle(title)
                    resolve()

                    if (!isVerbose) {
                      streamPreview.clear()
                    }
                  } else {
                    const msg = `exited with code ${code}`
                    setError(msg)
                    reject(new Error(msg))
                  }
                })

                child.on("error", (err) => {
                  setError(err.message)
                  reject(err)
                })
              })
            },
            { previewLines: isVerbose ? 100 : 10 },
          )

          return registeredTask
        },
        ),
        {
          concurrency: 1,
          stopOnError: true,
        },
      ),
      { showTime: true },
    ),
  ),
  {
    concurrency: taskGroups.length,
    stopOnError: false,
  },
)
