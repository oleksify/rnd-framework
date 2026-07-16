#!/usr/bin/env node
// Drives real headless Chrome via the Chrome DevTools Protocol (CDP) to prove
// a generated HTML report renders offline with a clean console. Node's
// built-in WebSocket and fetch are the only dependencies -- no npm installs.
//
// Usage:
//   node render-check.mjs <report.html> [--assert <expr-or-file>]...
//
// Each --assert value is either a path to an existing file (its contents are
// read as a JS expression) or an inline JS expression string. It is evaluated
// in the page's Runtime context via Runtime.evaluate; a falsy result or a
// thrown exception is recorded as a failure.
//
// Exit codes:
//   0  clean render (or a loud SKIP when the Chrome binary is absent)
//   1  a console error, an uncaught exception, or a failed --assert predicate

import { spawn } from 'node:child_process'
import { existsSync, mkdtempSync, readFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'

const DEFAULT_CHROME_BIN = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const DEVTOOLS_PORT_REGEX = /ws:\/\/127\.0\.0\.1:(\d+)\/devtools\/browser/
const LAUNCH_TIMEOUT_MS = 15000
const NAVIGATE_TIMEOUT_MS = 15000
const SETTLE_MS = 250

// -- pure helpers -------------------------------------------------------

const resolveChromeBinary = () => process.env.RND_CHROME_BIN || DEFAULT_CHROME_BIN

const resolveAssertExpression = (arg) => (existsSync(arg) ? readFileSync(arg, 'utf8') : arg)

const toFileUrl = (path) => `file://${resolve(path)}`

const parseAssertFlags = (argv) => {
  const expressions = []

  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--assert') {
      expressions.push(resolveAssertExpression(argv[i + 1]))
      i += 1
    }
  }

  return expressions
}

// -- CDP transport --------------------------------------------------------

const waitForDevToolsPort = (chromeProcess) =>
  new Promise((resolvePort, reject) => {
    const timer = setTimeout(
      () => reject(new Error('timed out waiting for the Chrome DevTools port')),
      LAUNCH_TIMEOUT_MS
    )

    const onExit = (code) => reject(new Error(`Chrome exited before opening a DevTools port (code ${code})`))

    chromeProcess.on('error', reject)
    chromeProcess.on('exit', onExit)

    chromeProcess.stderr.on('data', (chunk) => {
      const match = DEVTOOLS_PORT_REGEX.exec(chunk.toString())

      if (match) {
        clearTimeout(timer)
        chromeProcess.off('exit', onExit)
        resolvePort(Number(match[1]))
      }
    })
  })

const waitForPageTarget = async (port) => {
  const deadline = Date.now() + LAUNCH_TIMEOUT_MS

  while (Date.now() < deadline) {
    const targets = await fetch(`http://127.0.0.1:${port}/json`).then((r) => r.json())
    const page = targets.find((t) => t.type === 'page')

    if (page) return page

    await new Promise((r) => setTimeout(r, 100))
  }

  throw new Error('timed out waiting for a page target')
}

class CdpSession {
  constructor(ws) {
    this.ws = ws
    this.nextId = 1
    this.pending = new Map()
    this.listeners = new Map()

    ws.addEventListener('message', (event) => {
      const message = JSON.parse(event.data)

      if (message.id !== undefined && this.pending.has(message.id)) {
        const { resolve: resolvePending, reject: rejectPending } = this.pending.get(message.id)
        this.pending.delete(message.id)
        message.error ? rejectPending(new Error(message.error.message)) : resolvePending(message.result)
        return
      }

      if (message.method) {
        for (const handler of this.listeners.get(message.method) || []) {
          handler(message.params)
        }
      }
    })
  }

  send(method, params = {}) {
    const id = this.nextId++

    return new Promise((resolvePending, rejectPending) => {
      this.pending.set(id, { resolve: resolvePending, reject: rejectPending })
      this.ws.send(JSON.stringify({ id, method, params }))
    })
  }

  on(method, handler) {
    const handlers = this.listeners.get(method) || []
    handlers.push(handler)
    this.listeners.set(method, handlers)
  }
}

const connectCdp = (wsUrl) =>
  new Promise((resolveConnect, reject) => {
    const ws = new WebSocket(wsUrl)
    ws.addEventListener('open', () => resolveConnect(new CdpSession(ws)))
    ws.addEventListener('error', reject)
  })

// -- render check -----------------------------------------------------------

const runReportCheck = async (reportPath, assertExpressions) => {
  const failures = []
  const chromeBin = resolveChromeBinary()
  const userDataDir = mkdtempSync(join(tmpdir(), 'render-check-'))

  // Launch on about:blank and Page.navigate only after Runtime/Log listeners
  // are subscribed -- launching straight at the report's file:// URL would
  // race the CDP handshake against the page's own script execution, and an
  // exception thrown during initial parse could fire before we are listening
  // and be silently missed.
  const chromeProcess = spawn(chromeBin, [
    '--headless=new',
    '--disable-gpu',
    '--remote-debugging-port=0',
    `--user-data-dir=${userDataDir}`,
    'about:blank',
  ])

  try {
    const port = await waitForDevToolsPort(chromeProcess)
    const target = await waitForPageTarget(port)
    const session = await connectCdp(target.webSocketDebuggerUrl)

    session.on('Runtime.exceptionThrown', (params) => {
      const detail = params.exceptionDetails
      failures.push(`uncaught exception: ${detail.exception?.description || detail.text}`)
    })

    session.on('Runtime.consoleAPICalled', (params) => {
      if (params.type !== 'error') return

      const text = params.args.map((a) => a.value ?? a.description ?? '').join(' ')
      failures.push(`console error: ${text}`)
    })

    await session.send('Runtime.enable')
    await session.send('Log.enable')
    await session.send('Page.enable')

    const loadEvent = new Promise((r) => session.on('Page.loadEventFired', r))

    await session.send('Page.navigate', { url: toFileUrl(reportPath) })
    await Promise.race([
      loadEvent,
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('timed out waiting for the page load event')), NAVIGATE_TIMEOUT_MS)
      ),
    ])
    await new Promise((r) => setTimeout(r, SETTLE_MS))

    for (const expr of assertExpressions) {
      const result = await session.send('Runtime.evaluate', {
        expression: expr,
        returnByValue: true,
        awaitPromise: true,
      })

      if (result.exceptionDetails) {
        const detail = result.exceptionDetails
        failures.push(`predicate threw: ${expr} -> ${detail.exception?.description || detail.text}`)
      } else if (!result.result.value) {
        failures.push(`predicate failed: ${expr}`)
      }
    }

    return failures
  } finally {
    chromeProcess.kill()
  }
}

// -- entry point --------------------------------------------------------

const main = async () => {
  const [reportPath, ...rest] = process.argv.slice(2)

  if (!reportPath) {
    console.error('usage: node render-check.mjs <report.html> [--assert <expr-or-file>]...')
    process.exit(1)
  }

  const chromeBin = resolveChromeBinary()

  if (!existsSync(chromeBin)) {
    console.log(`SKIP: Chrome not found at ${chromeBin}`)
    process.exit(0)
  }

  if (!existsSync(reportPath)) {
    console.error(`report not found: ${reportPath}`)
    process.exit(1)
  }

  const assertExpressions = parseAssertFlags(rest)
  const failures = await runReportCheck(reportPath, assertExpressions)

  if (failures.length === 0) {
    console.log(`OK: ${reportPath} rendered offline with a clean console`)
    process.exit(0)
  }

  console.error(`FAIL: ${reportPath}`)
  for (const failure of failures) {
    console.error(`  - ${failure}`)
  }
  process.exit(1)
}

main().catch((err) => {
  console.error(`FAIL: ${err.message}`)
  process.exit(1)
})
