#!/usr/bin/env node
// Headless determinism gate for a generated rnd-explain report.
//
// Runs the SAME validation routine the report runs at load (window.__VALIDATE_REPORT__),
// but from node against a candidate document before it is written. It reports a
// distinct rejection class per violation so the pre-save step and the smoke
// check can gate on a bad or incomplete island without opening a browser.
//
// Usage:
//   node report-validate.js <report.html>
//       Validate a full self-contained report (runtime, schema, validator, and
//       island are all read from that one file).
//
//   node report-validate.js --island <island.md> [--template <template.html>]
//       Validate a candidate island against a template's inlined runtime,
//       schema, and validator. --template defaults to the sibling template.html.
//
// Output: a JSON object { ok, violations: [{ code, message }] } on stdout.
// Exit code: 0 when ok, 1 when any violation is found (or on a usage error).

'use strict'

const { readFileSync, existsSync } = require('node:fs')
const { join, resolve } = require('node:path')

const DEFAULT_TEMPLATE = join(__dirname, 'template.html')

// -- extraction -----------------------------------------------------------

// Slice out the content of the first <script> block whose body contains a
// known marker. Inline scripts cannot contain a literal </script>, so the
// first </script> after the marker's opening tag closes the block cleanly.
const scriptContaining = (html, marker) => {
  const idx = html.indexOf(marker)

  if (idx < 0) return null

  const open = html.lastIndexOf('<script', idx)
  const gt = html.indexOf('>', open)
  const close = html.indexOf('</script>', gt)

  return html.slice(gt + 1, close)
}

const islandSource = (html) => {
  const open = html.indexOf('<script type="text/markdoc" id="doc">')

  if (open < 0) return null

  const gt = html.indexOf('>', open)
  const close = html.indexOf('</script>', gt)

  return html.slice(gt + 1, close)
}

// Reconstruct the browser trio (runtime, schema, validator) from a template's
// inlined script blocks under a minimal fake window, then hand back the
// validator function plus the resolved config so it can run under node.
const loadValidator = (templateHtml) => {
  const bundleSrc = scriptContaining(templateHtml, 'var Markdoc=(()=>')
  const configSrc = scriptContaining(templateHtml, 'window.__MARKDOC_CONFIG__ = (function')
  const validatorSrc = scriptContaining(templateHtml, 'window.__VALIDATE_REPORT__ = (function')

  if (!bundleSrc) throw new Error('inlined Markdoc bundle not found in template')
  if (!configSrc) throw new Error('window.__MARKDOC_CONFIG__ not found in template')
  if (!validatorSrc) throw new Error('window.__VALIDATE_REPORT__ not found in template')

  const markdoc = new Function(bundleSrc + '\nreturn Markdoc;')()
  const win = { Markdoc: markdoc }

  new Function('window', configSrc)(win)
  new Function('window', validatorSrc)(win)

  return { markdoc, config: win.__MARKDOC_CONFIG__, validate: win.__VALIDATE_REPORT__ }
}

// -- argument parsing -----------------------------------------------------

const parseArgs = (argv) => {
  const opts = { report: null, island: null, template: DEFAULT_TEMPLATE }

  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--island') {
      opts.island = argv[i + 1]
      i += 1
    } else if (argv[i] === '--template') {
      opts.template = argv[i + 1]
      i += 1
    } else if (!opts.report) {
      opts.report = argv[i]
    }
  }

  return opts
}

// -- entry point ----------------------------------------------------------

const main = () => {
  const opts = parseArgs(process.argv.slice(2))

  if (!opts.report && !opts.island) {
    console.error('usage: node report-validate.js <report.html> | --island <island.md> [--template <template.html>]')
    process.exit(1)
  }

  const templatePath = resolve(opts.report ? opts.report : opts.template)

  if (!existsSync(templatePath)) {
    console.error(`file not found: ${templatePath}`)
    process.exit(1)
  }

  const templateHtml = readFileSync(templatePath, 'utf8')
  const { markdoc, config, validate } = loadValidator(templateHtml)

  let source

  if (opts.island) {
    const islandPath = resolve(opts.island)

    if (!existsSync(islandPath)) {
      console.error(`island file not found: ${islandPath}`)
      process.exit(1)
    }

    source = readFileSync(islandPath, 'utf8')
  } else {
    source = islandSource(templateHtml)

    if (source == null) {
      console.error('no markdoc island (<script type="text/markdoc" id="doc">) found in report')
      process.exit(1)
    }
  }

  const result = validate({ markdoc, config, islandSource: source })

  console.log(JSON.stringify(result, null, 2))
  process.exit(result.ok ? 0 : 1)
}

main()
