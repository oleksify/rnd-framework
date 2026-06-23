#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
APP_JS="${REPO_ROOT}/site/app.js"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

printf '\n--- site-renderer-safety ---\n'

node_output=''
node_exit=0
node_output="$(
  APP_JS="$APP_JS" node <<'NODE'
const fs = require("fs");
const vm = require("vm");

const appPath = process.env.APP_JS;
const source = fs.readFileSync(appPath, "utf8");

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function createElement(tagName) {
  return {
    tagName: String(tagName).toUpperCase(),
    className: "",
    children: [],
    attributes: {},
    innerHTML: "",
    textContent: "",
    id: "",
    appendChild(child) {
      this.children.push(child);
      return child;
    },
    replaceChildren(...children) {
      this.children = children;
    },
    setAttribute(name, value) {
      this.attributes[name] = String(value);
    },
    getBoundingClientRect() {
      return { top: 0, bottom: 0 };
    },
    querySelectorAll() {
      return [];
    },
    scrollIntoView() {},
    classList: {
      add() {},
      remove() {},
    },
  };
}

function createEnvironment(fetchImpl, parseImpl) {
  const elements = {
    content: createElement("main"),
    "toc-list": createElement("ol"),
    toc: { ...createElement("nav"), scrollTop: 0 },
  };
  const document = {
    createElement,
    getElementById(id) {
      return elements[id] || null;
    },
  };
  const sandbox = {
    module: { exports: {} },
    exports: {},
    console,
    document,
    fetch: fetchImpl,
    marked: { parse: parseImpl },
    location: { hash: "" },
    IntersectionObserver: class {
      observe() {}
    },
  };

  vm.runInNewContext(source, sandbox, { filename: appPath });
  return { elements, exports: sandbox.module.exports };
}

(async () => {
  {
    const { exports } = createEnvironment(async () => {
      throw new Error("fetch should not run");
    }, () => "");
    const sanitized = exports.sanitizeRenderedHtml(
      '<h2>Visible heading</h2><details><summary>More</summary><img src="x" onerror="boom()"><script>alert(1)</script><a href="javascript:alert(2)">bad</a></details>'
    );

    assert(!sanitized.includes("<script"), "script tags should be removed");
    assert(!sanitized.includes("onerror="), "event handler attributes should be removed");
    assert(!sanitized.includes("javascript:"), "javascript: URLs should be removed");
    assert(sanitized.includes("<details>"), "safe details markup should remain");
    assert(sanitized.includes("<h2>Visible heading</h2>"), "heading markup should remain");
  }

  {
    const { elements, exports } = createEnvironment(async (url) => {
      if (url === "docs/manifest.json") {
        return {
          ok: true,
          async text() {
            return '[{"file":"intro.md"}]';
          },
        };
      }
      return {
        ok: true,
        async text() {
          return "## Intro";
        },
      };
    }, () => '<h2>Intro</h2><details><summary>Safe</summary><img src="x" onload="boom()"></details><script>alert(1)</script>');

    await exports.render();

    assert(elements.content.children.length === 1, "render should replace content with one section");
    assert(elements.content.children[0].tagName === "SECTION", "render should create section elements");
    assert(elements.content.children[0].innerHTML.includes("<h2>Intro</h2>"), "render should keep heading HTML");
    assert(elements.content.children[0].innerHTML.includes("<details>"), "render should keep safe details markup");
    assert(!elements.content.children[0].innerHTML.includes("<script"), "render should strip script tags");
    assert(!elements.content.children[0].innerHTML.includes("onload="), "render should strip event handlers");
  }

  {
    const { elements, exports } = createEnvironment(async () => {
      throw new Error('<img src=x onerror="boom()"> manifest failed');
    }, () => "");

    await exports.render();

    assert(elements.content.children.length === 1, "manifest error should render one error node");
    assert(elements.content.children[0].className === "error", "manifest error should use the error class");
    assert(
      elements.content.children[0].textContent ===
        'Could not load docs manifest (<img src=x onerror="boom()"> manifest failed).',
      "manifest error text should be preserved literally"
    );
    assert(elements.content.children[0].innerHTML === "", "manifest error should not use innerHTML");
  }

  {
    let callCount = 0;
    const { elements, exports } = createEnvironment(async () => {
      callCount += 1;
      if (callCount === 1) {
        return {
          ok: true,
          async text() {
            return '[{"file":"intro.md"}]';
          },
        };
      }
      throw new Error("<script>alert(1)</script> section failed");
    }, () => "");

    await exports.render();

    assert(elements.content.children.length === 1, "section error should render one error node");
    assert(elements.content.children[0].className === "error", "section error should use the error class");
    assert(
      elements.content.children[0].textContent ===
        "Could not load a docs section (<script>alert(1)</script> section failed).",
      "section error text should be preserved literally"
    );
    assert(elements.content.children[0].innerHTML === "", "section error should not use innerHTML");
  }

  console.log("ok site renderer safety");
})().catch((error) => {
  console.error(error.stack || String(error));
  process.exit(1);
});
NODE
)" || node_exit=$?

assert_eq \
  "site renderer safety smoke test exits 0" \
  "0" \
  "$node_exit"

assert_contains \
  "site renderer safety smoke test reports success" \
  "ok site renderer safety" \
  "$node_output"

report
