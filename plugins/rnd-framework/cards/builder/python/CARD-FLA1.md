---
id: FLA1
role: builder
language: python
tags: [boundaries, control-flow, error-handling]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Access Flask context-locals (current_app, g, request) only inside an active request or application context; never capture them in module-level variables or closures that outlive the context.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle for Flask: `current_app` and `request` are context-locals that proxy to the active context — capturing the proxy object outside that context yields a detached, broken reference.

**Good:**
```python
from flask import Flask, current_app, jsonify

app = Flask(__name__)
app.config["API_KEY"] = "secret"

@app.route("/status")
def status():
    key = current_app.config["API_KEY"]   # accessed inside request context
    return jsonify({"key_set": bool(key)})
```

**Worse:**
```python
from flask import Flask, current_app

app = Flask(__name__)
app.config["API_KEY"] = "secret"

# captured at import time — outside any context
_api_key = current_app.config["API_KEY"]   # RuntimeError: working outside of application context

@app.route("/status")
def status():
    return jsonify({"key_set": bool(_api_key)})
```

**Why good is better:** Flask uses a thread-local (or context-var) stack to bind `current_app` to the active application context for the duration of a request. Accessing `current_app` outside a pushed context raises `RuntimeError: working outside of application context`; even if it were silently available, it would capture the value at import time and miss any runtime config changes. Read config, `g`, and request attributes inside the handler or a helper that is always called within a request; use `app.app_context()` explicitly when you need a context in background code.
