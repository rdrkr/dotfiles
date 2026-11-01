/**
 * Copyright (c) 2026, Ronen Druker. All rights reserved.
 *
 * Minimal, dependency-free progress renderer for run-tasks.
 *
 * It is built to stay flicker-free in terminal multiplexers (tmux, psmux, zellij, ...):
 * - only the lines that changed since the previous frame are rewritten, in place, so the
 *   region is never erased and redrawn as a whole;
 * - every frame is one write wrapped in synchronized-output markers (DEC mode 2026), which
 *   supporting terminals apply atomically and others ignore;
 * - the live region is capped to the terminal height (and every line to its width), because
 *   the cursor cannot move back up into scrollback, and an overflowing region corrupts
 *   every following frame;
 * - frames are drawn at a fixed, low rate instead of once per output chunk;
 * - finished stages are written out once and leave the live region for good.
 * When stdout is not a terminal, finished tasks are logged as plain lines instead.
 */

import { styleText } from "node:util"

/**
 * Lifecycle state of a single task
 */
export type TaskStatus = "pending" | "running" | "success" | "skipped" | "error"

/**
 * Text style accepted by node's styleText (a single format or a list of formats)
 */
type Style = Parameters<typeof styleText>[0]

/**
 * A piece of a rendered line: its text and the style it is painted with
 */
type Segment = readonly [text: string, style?: Style]

/**
 * Output stream a task can write to
 */
export type OutputStream = "stdout" | "stderr"

/**
 * The part of a writable stream the renderer uses; a terminal when isTTY is set
 */
export type Output = Pick<NodeJS.WriteStream, "write"> &
  Partial<Pick<NodeJS.WriteStream, "isTTY" | "columns" | "rows" | "hasColors">>

/** Most output lines kept per task, regardless of how many its preview shows */
const MAX_BUFFERED_LINES = 200

/** Fewest output lines shown for a failed task once its stage is done */
const MIN_ERROR_LINES = 30

/** Interval between live frames, in milliseconds */
const FRAME_INTERVAL = 100

/** Spinner frames shown next to running tasks and groups */
const SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

/** ESC-introduced terminal sequences: CSI, OSC (BEL or ST terminated) and two-character escapes */
const ESCAPE_SEQUENCES = /\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)?|\x1b[@-_]/g

/** Remaining control characters, tabs excluded */
const CONTROL_CHARACTERS = /[\x00-\x08\x0b-\x1f\x7f]/g

/** Begin and end synchronized update (DEC private mode 2026) */
const SYNC_BEGIN = "\x1b[?2026h"
const SYNC_END = "\x1b[?2026l"

/** Hide and show the cursor */
const CURSOR_HIDE = "\x1b[?25l"
const CURSOR_SHOW = "\x1b[?25h"

/**
 * Turn one line of child output into printable text: keep what a terminal would show after
 * carriage returns (progress bars redraw a line with \r), then drop escape sequences and
 * control characters, which would otherwise break the renderer's line and width accounting
 */
export function sanitizeLine(raw: string): string {
  const segments = raw.split("\r")
  const visible = segments.findLast((s) => s.length > 0) ?? ""
  return visible.replace(ESCAPE_SEQUENCES, "").replace(CONTROL_CHARACTERS, "").replace(/\t/g, "  ")
}

/**
 * Format an elapsed duration as "12s" or "3m 05s"
 */
export function formatDuration(ms: number): string {
  const seconds = Math.floor(ms / 1000)
  if (seconds < 60) {
    return `${seconds}s`
  }
  return `${Math.floor(seconds / 60)}m ${String(seconds % 60).padStart(2, "0")}s`
}

/**
 * State of a single task, updated by the runner and drawn by the renderer
 */
export class TaskView {
  /** Current lifecycle state */
  status: TaskStatus = "pending"
  /** Detail shown after the title, such as a skip reason or an exit code */
  message = ""
  /** Complete output lines, oldest first, capped at MAX_BUFFERED_LINES */
  readonly lines: string[] = []
  /** Unterminated trailing text of each output stream */
  private readonly partials: Record<OutputStream, string> = { stdout: "", stderr: "" }

  /**
   * @param title Title shown for the task
   * @param previewLines Most output lines shown under the task
   * @param keepOutput Keep the output visible after the task succeeds
   */
  constructor(
    readonly title: string,
    readonly previewLines: number,
    readonly keepOutput: boolean,
  ) {}

  /**
   * Mark the task as running
   */
  start(): void {
    this.status = "running"
  }

  /**
   * Add a chunk of output from one of the task's streams; partial lines are buffered per
   * stream so interleaved stdout and stderr chunks never splice into each other
   */
  append(stream: OutputStream, chunk: string): void {
    const parts = (this.partials[stream] + chunk).split("\n")
    this.partials[stream] = parts.pop() ?? ""
    for (const part of parts) {
      this.push(sanitizeLine(part))
    }
  }

  /**
   * Output lines to show, including any unterminated line still being written
   */
  displayLines(): string[] {
    const pending = [this.partials.stdout, this.partials.stderr].map(sanitizeLine).filter(Boolean)
    return pending.length > 0 ? [...this.lines, ...pending] : this.lines
  }

  /**
   * Mark the task as successful
   */
  succeed(): void {
    this.finish("success", "")
  }

  /**
   * Mark the task as skipped, with the reason
   */
  skip(reason: string): void {
    this.finish("skipped", reason)
  }

  /**
   * Mark the task as failed, with the reason
   */
  fail(reason: string): void {
    this.finish("error", reason)
  }

  /**
   * Whether the task has reached a final state
   */
  get done(): boolean {
    return this.status === "success" || this.status === "skipped" || this.status === "error"
  }

  /**
   * Settle the task: flush buffered partial lines and record the final state
   */
  private finish(status: TaskStatus, message: string): void {
    for (const stream of ["stdout", "stderr"] as const) {
      if (this.partials[stream]) {
        this.push(sanitizeLine(this.partials[stream]))
        this.partials[stream] = ""
      }
    }
    this.status = status
    this.message = message
  }

  /**
   * Append one finished line, dropping the oldest once the buffer is full
   */
  private push(line: string): void {
    this.lines.push(line)
    if (this.lines.length > MAX_BUFFERED_LINES) {
      this.lines.shift()
    }
  }
}

/**
 * State of a task group: its tasks and when it started and ended
 */
export class GroupView {
  /** When the group's first task started, in epoch milliseconds */
  startedAt?: number
  /** When the group's last task ended, in epoch milliseconds */
  endedAt?: number

  /**
   * @param title Title shown above the group's tasks
   * @param tasks The group's tasks, in run order
   */
  constructor(
    readonly title: string,
    readonly tasks: TaskView[],
  ) {}

  /**
   * Record the group's start time
   */
  start(): void {
    this.startedAt = Date.now()
  }

  /**
   * Record the group's end time
   */
  end(): void {
    this.endedAt = Date.now()
  }

  /**
   * Overall state: running once started, then error if any task failed, success otherwise
   */
  get status(): TaskStatus {
    if (this.startedAt === undefined) {
      return "pending"
    }
    if (this.endedAt === undefined) {
      return "running"
    }
    return this.tasks.some((t) => t.status === "error") ? "error" : "success"
  }
}

/**
 * Draws task groups to a terminal, or logs finished tasks when the output is not a terminal
 */
export class Renderer {
  /** Whether a live, redrawn region is used (output is a capable terminal) */
  readonly live: boolean
  /** Whether output is colored */
  private readonly color: boolean
  /** Groups of the stage being drawn */
  private groups: GroupView[] = []
  /** Lines currently on screen in the live region, top to bottom */
  private previous: string[] = []
  /** Timer driving live frames while a stage runs */
  private timer?: NodeJS.Timeout

  /**
   * @param out Stream to draw to
   * @param env Environment consulted for TERM
   */
  constructor(
    private readonly out: Output = process.stdout,
    env: NodeJS.ProcessEnv = process.env,
  ) {
    this.live = Boolean(out.isTTY) && env.TERM !== "dumb"
    this.color = Boolean(out.isTTY) && (out.hasColors?.() ?? false)
  }

  /**
   * Start drawing a stage's groups; in live mode, frames are drawn until endStage()
   */
  beginStage(groups: GroupView[]): void {
    this.groups = groups
    if (!this.live) {
      return
    }
    this.out.write(CURSOR_HIDE)
    this.render()
    this.timer = setInterval(() => this.render(), FRAME_INTERVAL)
  }

  /**
   * Report a task that just finished; in plain mode it is logged right away, together with
   * its output when it failed or keeps its output
   */
  taskFinished(group: GroupView, task: TaskView): void {
    if (this.live) {
      return
    }
    const width = Number.POSITIVE_INFINITY
    const lines = [
      this.paint([this.icon(task.status), [" "], [`${group.title} › `, "dim"], ...this.titleSegments(task)], width),
      ...this.outputSegments(task, true).map((segments) => this.paint(segments, width)),
    ]
    this.out.write(lines.map((line) => `${line}\n`).join(""))
  }

  /**
   * Finish the stage: draw its final, uncapped frame, which stays on screen as plain output
   */
  endStage(): void {
    if (!this.live) {
      return
    }
    clearInterval(this.timer)
    this.timer = undefined
    this.draw(this.frame(true))
    this.previous = []
    this.out.write(CURSOR_SHOW)
  }

  /**
   * Stop drawing because the run is being aborted: leave the last frame and restore the cursor
   */
  abort(): void {
    if (this.timer) {
      this.endStage()
    }
  }

  /**
   * Draw one live frame
   */
  render(): void {
    this.draw(this.frame(false))
  }

  /**
   * Build the lines of a frame. A live frame is capped to the terminal height, sharing the
   * free rows fairly between the outputs of running and failed tasks; the final frame shows
   * each task's output in full (up to its preview size) and nothing for quiet successes.
   */
  private frame(final: boolean): string[] {
    const width = Math.max(20, (this.out.columns ?? 80) - 1)
    const maxRows = Math.max(1, (this.out.rows ?? 24) - 1)

    const tasks = this.groups.flatMap((g) => g.tasks)
    const outputs = tasks.map((t) => this.outputSegments(t, final))
    const quota = final ? outputs.map((o) => o.length) : this.shareRows(outputs, maxRows - this.groups.length - tasks.length)

    const lines: string[] = []
    let index = 0
    for (const group of this.groups) {
      lines.push(this.paint(this.groupSegments(group), width))
      for (const task of group.tasks) {
        lines.push(this.paint([["  "], ...this.taskSegments(task)], width))
        const output = outputs[index] ?? []
        const shown = quota[index] ?? 0
        for (const segments of output.slice(output.length - shown)) {
          lines.push(this.paint(segments, width))
        }
        index++
      }
    }
    return final ? lines : lines.slice(-maxRows)
  }

  /**
   * Split free rows between outputs by water-filling: small outputs get all their lines and
   * leave what they do not use to the larger ones
   */
  private shareRows(outputs: Segment[][][], freeRows: number): number[] {
    const quota = outputs.map(() => 0)
    let remaining = Math.max(0, freeRows)
    const wanting = outputs
      .map((output, i) => ({ i, want: output.length }))
      .filter(({ want }) => want > 0)
      .sort((a, b) => a.want - b.want)

    wanting.forEach(({ i, want }, position) => {
      const share = Math.floor(remaining / (wanting.length - position))
      quota[i] = Math.min(want, share)
      remaining -= quota[i] ?? 0
    })
    return quota
  }

  /**
   * Write a frame, rewriting only the lines that differ from what is on screen. The cursor
   * rests at the start of the line below the region between frames.
   */
  private draw(lines: string[]): void {
    const previous = this.previous
    let body = ""
    let changed = lines.length !== previous.length

    lines.forEach((line, i) => {
      if (i < previous.length && previous[i] === line) {
        body += "\x1b[1E"
      } else {
        body += `${line}\x1b[K\n`
        changed = true
      }
    })
    if (!changed) {
      return
    }
    if (lines.length < previous.length) {
      body += "\x1b[J"
    }

    const up = previous.length > 0 ? `\x1b[${previous.length}F` : ""
    this.out.write(SYNC_BEGIN + up + body + SYNC_END)
    this.previous = lines
  }

  /**
   * Segments of a group's title line: status icon, title and elapsed time
   */
  private groupSegments(group: GroupView): Segment[] {
    const segments: Segment[] = [this.icon(group.status), [" "], [group.title, "bold"]]
    if (group.startedAt !== undefined) {
      segments.push([` (${formatDuration((group.endedAt ?? Date.now()) - group.startedAt)})`, "dim"])
    }
    return segments
  }

  /**
   * Segments of a task's line: status icon, title and message
   */
  private taskSegments(task: TaskView): Segment[] {
    return [this.icon(task.status), [" "], ...this.titleSegments(task)]
  }

  /**
   * Segments of a task's title and message, the message colored by the task's state
   */
  private titleSegments(task: TaskView): Segment[] {
    const segments: Segment[] = [[task.title, task.status === "pending" ? "dim" : undefined]]
    if (task.message) {
      segments.push([` → ${task.message}`, task.status === "error" ? "red" : "yellow"])
    }
    return segments
  }

  /**
   * Indented output lines to show under a task: the tail of a running task's output while
   * live, and once settled only for failures and for tasks that keep their output
   */
  private outputSegments(task: TaskView, final: boolean): Segment[][] {
    const failed = task.status === "error"
    const visible =
      task.status === "running" || failed || (final && task.status === "success" && task.keepOutput)
    if (!visible) {
      return []
    }
    const limit = final && failed ? Math.max(task.previewLines, MIN_ERROR_LINES) : task.previewLines
    return task
      .displayLines()
      .slice(-limit)
      .map((line) => [["    "], [line, failed ? undefined : "dim"]])
  }

  /**
   * Status icon segment for a state; running ones spin with the wall clock
   */
  private icon(status: TaskStatus): Segment {
    switch (status) {
      case "pending":
        return ["◌", "dim"]
      case "running":
        return [SPINNER[Math.floor(Date.now() / FRAME_INTERVAL) % SPINNER.length] ?? "", "cyan"]
      case "success":
        return ["✔", "green"]
      case "skipped":
        return ["⚠", "yellow"]
      case "error":
        return ["✖", "red"]
    }
  }

  /**
   * Join segments into one line no wider than width visible characters, truncating with an
   * ellipsis; truncation happens before styling so escape codes never count toward the width
   */
  private paint(segments: Segment[], width: number): string {
    let room = width
    let line = ""
    for (const [text, style] of segments) {
      if (room <= 0) {
        break
      }
      const chars = [...text]
      const piece = chars.length > room ? `${chars.slice(0, room - 1).join("")}…` : text
      room -= Math.min(chars.length, room)
      line += style ? this.style(piece, style) : piece
    }
    return line
  }

  /**
   * Style text when color is enabled
   */
  private style(text: string, style: Style): string {
    return this.color ? styleText(style, text, { validateStream: false }) : text
  }
}
