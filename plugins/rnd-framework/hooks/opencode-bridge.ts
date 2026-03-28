// opencode-bridge.ts — Thin Shell Bridge for rnd-framework hooks under OpenCode.
//
// Translates OpenCode hook events into calls to existing shell scripts.
// Shell scripts remain the single source of truth for all hook logic.
//
// Hook mapping:
//   tool.execute.before  → prefer-tools.sh, read-gate.sh, write-gate.sh, glob-grep-gate.sh
//   tool.execute.after   → post-tool-use.sh, observation-mask.sh
//   event (file.edited)  → file-changed.sh
//   session.compacting   → pre-compact.sh + post-compact.sh
//   chat.system.transform → injects session-start.sh context
//   shell.env            → sets CLAUDE_PLUGIN_ROOT for shell tool executions
//
// Pre-conditions:
//   - Runs under Bun (OpenCode's runtime)
//   - Shell scripts are in the same directory as this file
//   - bash and jq are available on PATH

import { resolve, join } from "path"
import type { Plugin } from "@opencode-ai/plugin"

const HOOKS_DIR = import.meta.dir
const PLUGIN_ROOT = resolve(HOOKS_DIR, "..")

// ---------------------------------------------------------------------------
// Tool name translation: OpenCode lowercase → Claude Code PascalCase
// ---------------------------------------------------------------------------

const TOOL_NAME_MAP: Record<string, string> = {
  bash: "Bash",
  read: "Read",
  write: "Write",
  edit: "Edit",
  glob: "Glob",
  grep: "Grep",
}

// ---------------------------------------------------------------------------
// Hook routing tables
// ---------------------------------------------------------------------------

const PRE_TOOL_ROUTES: Record<string, string> = {
  bash: "bash-gate.sh",
  read: "read-gate.sh",
  write: "write-gate.sh",
  edit: "write-gate.sh",
  glob: "glob-grep-gate.sh",
  grep: "glob-grep-gate.sh",
}

const POST_TOOL_ROUTES: Record<string, string> = {
  write: "post-dispatch.sh",
  edit: "post-dispatch.sh",
  bash: "post-dispatch.sh",
}

// ---------------------------------------------------------------------------
// Shell script runner
// ---------------------------------------------------------------------------

interface ScriptResult {
  exitCode: number
  stdout: string
  stderr: string
}

async function runScript(scriptName: string, stdinData: string): Promise<ScriptResult> {
  const scriptPath = join(HOOKS_DIR, scriptName)

  try {
    const proc = Bun.spawn(["bash", scriptPath], {
      stdin: new Response(stdinData),
      stdout: "pipe",
      stderr: "pipe",
      env: {
        ...process.env,
        CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT,
      },
    })

    const [stdout, stderr] = await Promise.all([
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
    ])
    const exitCode = await proc.exited

    return { exitCode, stdout: stdout.trim(), stderr: stderr.trim() }
  } catch {
    // Script missing or spawn failed — fail open (do not block the tool)
    return { exitCode: 0, stdout: "", stderr: "" }
  }
}

// ---------------------------------------------------------------------------
// Stdin JSON builders
//
// Our shell scripts expect JSON on stdin with these fields:
//   PreToolUse:  { tool_name, tool_input, agent_type }
//   PostToolUse: { tool_name, tool_input, tool_output: { stdout } }
// ---------------------------------------------------------------------------

function preToolUseJson(tool: string, args: Record<string, unknown>): string {
  return JSON.stringify({
    tool_name: TOOL_NAME_MAP[tool] ?? tool,
    tool_input: args ?? {},
    agent_type: "",
  })
}

function postToolUseJson(tool: string, args: Record<string, unknown>, output: string): string {
  return JSON.stringify({
    tool_name: TOOL_NAME_MAP[tool] ?? tool,
    tool_input: args ?? {},
    tool_output: { stdout: output },
  })
}

// ---------------------------------------------------------------------------
// Response parser: extract additionalContext from hook JSON output
// ---------------------------------------------------------------------------

function extractContext(stdout: string): string {
  if (!stdout) return ""
  try {
    const parsed = JSON.parse(stdout)
    return parsed?.hookSpecificOutput?.additionalContext ?? ""
  } catch {
    return ""
  }
}

// ---------------------------------------------------------------------------
// Plugin entry point
// ---------------------------------------------------------------------------

export default {
  id: "rnd-framework-bridge",

  server: (async ({ directory }) => {
    // Run session-start.sh at plugin init to bootstrap the RND session
    // and capture context for system prompt injection.
    const startResult = await runScript(
      "session-start.sh",
      JSON.stringify({ event: "startup" }),
    )
    const sessionContext = extractContext(startResult.stdout)

    return {
      // Inject session-start context into every LLM system prompt
      "experimental.chat.system.transform": async (_input, output) => {
        if (sessionContext) {
          output.system.push(sessionContext)
        }
      },

      // PreToolUse: route to the matching shell script, block if exit 2
      "tool.execute.before": async (input, output) => {
        const script = PRE_TOOL_ROUTES[input.tool]
        if (!script) return

        const result = await runScript(script, preToolUseJson(input.tool, output.args))

        // Exit 2 = block. Throw to prevent tool execution.
        if (result.exitCode === 2) {
          throw new Error(result.stderr || `Blocked by rnd-framework: ${script}`)
        }
        // Exit 0 = allow or no opinion. Tool proceeds normally.
      },

      // PostToolUse: route to the matching shell script (best-effort, non-blocking)
      "tool.execute.after": async (input, output) => {
        const script = POST_TOOL_ROUTES[input.tool]
        if (!script) return

        const stdinJson = postToolUseJson(input.tool, input.args, output.output ?? "")
        // Fire and forget — audit logging and observation masking should not
        // block the conversation even if the script fails.
        runScript(script, stdinJson).catch(() => {})
      },

      // Event bus: handle file.edited events
      event: async ({ event }) => {
        if (event.type === "file.edited") {
          const filePath = (event as Record<string, unknown>).properties
            ? ((event as Record<string, unknown>).properties as Record<string, unknown>)?.path ?? ""
            : ""
          if (filePath) {
            await runScript(
              "file-changed.sh",
              JSON.stringify({ file_path: filePath }),
            )
          }
        }
      },

      // Pre-compaction: save pipeline state, then inject restored context
      "experimental.session.compacting": async (_input, output) => {
        await runScript("pre-compact.sh", "{}")
        const postResult = await runScript("post-compact.sh", "{}")
        const ctx = extractContext(postResult.stdout)
        if (ctx) {
          output.context.push(ctx)
        }
      },

      // Inject CLAUDE_PLUGIN_ROOT into shell tool executions so that
      // scripts invoked via the bash tool can find plugin resources.
      "shell.env": async (_input, output) => {
        output.env.CLAUDE_PLUGIN_ROOT = PLUGIN_ROOT
      },
    }
  }) satisfies Plugin,
}
