/**
 * Copyright (c) 2026, Ronen Druker. All rights reserved.
 */

import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { homedir, tmpdir } from "node:os"
import { dirname, join } from "node:path"
import { after, test } from "node:test"
import { fileURLToPath } from "node:url"
import { stringify } from "yaml"

/** Directory containing this test and the runner under test */
const here = dirname(fileURLToPath(import.meta.url))

/** Local tsx CLI used to execute the runner; run through node so it needs no executable bit */
const tsx = join(here, "node_modules", "tsx", "dist", "cli.mjs")

/** Scratch directory for generated task files and task output */
const scratch = mkdtempSync(join(tmpdir(), "run-tasks-test-"))

after(() => rmSync(scratch, { recursive: true, force: true }))

/**
 * Write a task file containing the given groups, run the runner on it and return its exit status
 */
function runTasks(name: string, groups: unknown[]): number {
  const file = join(scratch, `${name}.yaml`)
  writeFileSync(file, stringify({ name, description: name, usage: name, groups }))

  const result = spawnSync(process.execPath, [tsx, join(here, "run-tasks.ts"), file], {
    encoding: "utf-8",
    timeout: 30_000,
  })
  if (result.error) {
    throw result.error
  }
  return result.status ?? -1
}

/**
 * Build a task running a bash script, with extra arguments available to the script as $1, $2, ...
 */
function bashTask(title: string, script: string, ...args: string[]) {
  return { title, command: "bash", args: ["-c", script, "bash", ...args] }
}

/**
 * Path of a file inside the scratch directory
 */
function scratchFile(name: string): string {
  return join(scratch, name)
}

test("runs later stages only after earlier stages finish, regardless of file order", () => {
  const log = scratchFile("stages.log")

  const status = runTasks("stages", [
    { title: "late", stage: 1, tasks: [bashTask("late", 'echo stage1 >> "$1"', log)] },
    { title: "early", tasks: [bashTask("early", 'sleep 1; echo stage0 >> "$1"', log)] },
  ])

  assert.equal(status, 0)
  assert.deepEqual(readFileSync(log, "utf-8").trim().split("\n"), ["stage0", "stage1"])
})

test("skips tasks whose command or requirement is missing without failing", () => {
  const skipped = scratchFile("skipped.marker")
  const ran = scratchFile("ran.marker")

  const status = runTasks("missing", [
    {
      title: "group",
      tasks: [
        { title: "missing command", command: "run-tasks-no-such-command", args: [] },
        { ...bashTask("missing requirement", 'touch "$1"', skipped), requires: ["run-tasks-no-such-command"] },
        bashTask("present", 'touch "$1"', ran),
      ],
    },
  ])

  assert.equal(status, 0)
  assert.equal(existsSync(skipped), false)
  assert.equal(existsSync(ran), true)
})

test("exits non-zero on failure but still runs the rest of the group and later stages", () => {
  const sameGroup = scratchFile("same-group.marker")
  const laterStage = scratchFile("later-stage.marker")

  const status = runTasks("failure", [
    { title: "group", tasks: [bashTask("fail", "exit 3"), bashTask("after failure", 'touch "$1"', sameGroup)] },
    { title: "later", stage: 1, tasks: [bashTask("later", 'touch "$1"', laterStage)] },
  ])

  assert.equal(status, 1)
  assert.equal(existsSync(sameGroup), true)
  assert.equal(existsSync(laterStage), true)
})

test("passes shell scripts through verbatim and expands only a leading tilde", () => {
  const verbatim = scratchFile("verbatim.txt")
  const tilde = scratchFile("tilde.txt")

  const status = runTasks("expansion", [
    {
      title: "group",
      tasks: [
        bashTask("script vars", 'LOCAL_VAR=kept; printf "%s|%s" "$LOCAL_VAR" "$2" > "$1"', verbatim, "$HOME and ~/x"),
        bashTask("leading tilde", 'printf "%s" "$2" > "$1"', tilde, "~/x"),
      ],
    },
  ])

  assert.equal(status, 0)
  assert.equal(readFileSync(verbatim, "utf-8"), "kept|$HOME and ~/x")
  assert.equal(readFileSync(tilde, "utf-8"), `${homedir()}/x`)
})
