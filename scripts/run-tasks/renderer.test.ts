/**
 * Copyright (c) 2026, Ronen Druker. All rights reserved.
 */

import assert from "node:assert/strict"
import { test } from "node:test"
import { formatDuration, GroupView, type Output, Renderer, sanitizeLine, TaskView } from "./renderer.ts"

/**
 * Fake terminal that records everything written to it
 */
class FakeTerminal implements Output {
  /** Every chunk written, in order */
  readonly writes: string[] = []
  /** Marks the fake as a terminal so the renderer draws live */
  readonly isTTY = true

  /**
   * @param columns Terminal width
   * @param rows Terminal height
   */
  constructor(
    readonly columns = 80,
    readonly rows = 24,
  ) {}

  /**
   * Record a chunk
   */
  write(chunk: string | Uint8Array): boolean {
    this.writes.push(String(chunk))
    return true
  }

  /**
   * Report no color support so frames are plain text
   */
  hasColors(): boolean {
    return false
  }
}

test("sanitizeLine keeps the last carriage-return segment and strips escapes", () => {
  assert.equal(sanitizeLine("10%\r50%\r100%"), "100%")
  assert.equal(sanitizeLine("done\r"), "done")
  assert.equal(sanitizeLine("\x1b[1;32mgreen\x1b[0m \x1b]8;;http://x\x07link\x1b]8;;\x07"), "green link")
  assert.equal(sanitizeLine("a\tb\x07"), "a  b")
})

test("formatDuration formats seconds and minutes", () => {
  assert.equal(formatDuration(12_400), "12s")
  assert.equal(formatDuration(185_000), "3m 05s")
})

test("TaskView buffers partial lines per stream and flushes them when done", () => {
  const view = new TaskView("t", 10, false)
  view.start()
  view.append("stdout", "out-a")
  view.append("stderr", "err\n")
  view.append("stdout", "-b\nrest")
  assert.deepEqual(view.lines, ["err", "out-a-b"])
  assert.deepEqual(view.displayLines(), ["err", "out-a-b", "rest"])
  view.succeed()
  assert.deepEqual(view.lines, ["err", "out-a-b", "rest"])
})

test("live renderer rewrites only changed lines and skips identical frames", () => {
  const term = new FakeTerminal()
  const renderer = new Renderer(term, { TERM: "xterm-256color" })
  const task = new TaskView("task", 10, false)
  const group = new GroupView("group", [task])

  renderer.beginStage([group])
  const afterFirst = term.writes.length
  renderer.render()
  assert.equal(term.writes.length, afterFirst, "an unchanged frame writes nothing")

  group.start()
  task.start()
  task.append("stdout", "hello\n")
  renderer.render()
  const frame = term.writes.at(-1) ?? ""
  assert.ok(frame.startsWith("\x1b[?2026h") && frame.endsWith("\x1b[?2026l"), "frames are synchronized")
  assert.ok(frame.includes("    hello\x1b[K\n"), "new output line is drawn")

  task.succeed()
  group.end()
  renderer.endStage()
  const final = term.writes.slice(afterFirst).join("")
  assert.ok(final.includes("✔ task"), "final frame shows the result")
  assert.ok(final.endsWith("\x1b[?25h"), "cursor is restored")
})

test("live frames never exceed the terminal size", () => {
  const term = new FakeTerminal(30, 8)
  const renderer = new Renderer(term, { TERM: "xterm" })
  const tasks = [new TaskView("first task with a very long title indeed", 10, false), new TaskView("second", 10, false)]
  const group = new GroupView("group", tasks)
  group.start()
  for (const t of tasks) {
    t.start()
    t.append("stdout", Array.from({ length: 20 }, (_, i) => `line ${i}`).join("\n") + "\n")
  }

  renderer.beginStage([group])
  const lines = (term.writes.at(-1) ?? "")
    .replace(/\x1b\[\?2026[hl]|\x1b\[\?25[hl]/g, "")
    .split("\x1b[K\n")
    .filter(Boolean)
  assert.ok(lines.length <= 7, `drew ${lines.length} lines in 8 rows`)
  assert.ok(lines.every((l) => [...l].length <= 29), "lines fit the width")
  renderer.abort()
})

test("plain renderer logs finished tasks with failure output", () => {
  const out: string[] = []
  const renderer = new Renderer({ write: (chunk: string | Uint8Array) => out.push(String(chunk)) > 0 })
  const task = new TaskView("broken", 10, false)
  const group = new GroupView("group", [task])
  renderer.beginStage([group])
  task.start()
  task.append("stderr", "boom\n")
  task.fail("exited with code 3")
  renderer.taskFinished(group, task)
  renderer.endStage()
  assert.equal(out.join(""), "✖ group › broken → exited with code 3\n    boom\n")
})
