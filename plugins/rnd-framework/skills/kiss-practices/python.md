# Python — KISS Rules

## Package Management

- Use `uv` instead of `pip`, `pip3`, or `pipx` — it is faster, handles lockfiles, and manages virtual environments in one tool
- Use `uv add`/`uv remove` to manage `pyproject.toml` dependencies — don't manually edit dependency lists
- Use `uvx` to run one-off CLI tools — don't install them globally with `pipx`
- Use `uv venv` for virtual environments — don't use `python -m venv` or `virtualenv`
- Use `uv sync` to reproduce environments from lockfiles — don't `pip freeze > requirements.txt`

## Code Quality

- Use `ruff` for both linting and formatting — don't install separate tools (flake8, black, isort, pylint)
- Run `ruff check --fix . && ruff format .` as a single pass — don't chain multiple linters
- Configure ruff in `pyproject.toml` under `[tool.ruff]` — don't create `.flake8`, `.isort.cfg`, or `setup.cfg` for linter config

## Project Structure

- Use `pyproject.toml` as the single project config — don't maintain `setup.py`, `setup.cfg`, and `requirements.txt` separately
- Don't create `__init__.py` files in every directory — implicit namespace packages work since Python 3.3; add `__init__.py` only when you need to export a public API or run initialization code
- Don't create a `utils.py` or `helpers.py` catch-all — put functions in the module where they're used

## Type Hints

- Use built-in generics (`list[str]`, `dict[str, int]`, `str | None`) — don't import from `typing` for types available as builtins since Python 3.10
- Don't annotate every local variable — let type checkers infer from assignment
- Don't create TypedDict for one-off structures — a plain dict or dataclass is clearer

## Data Classes and Models

- Use `@dataclass` for simple value objects — don't write `__init__`, `__repr__`, `__eq__` by hand
- Don't use `@dataclass` when a named tuple or plain tuple suffices — if it's just grouping 2-3 return values, a tuple is simpler
- Don't add validators, serializers, or factory methods to dataclasses until you need them

## Error Handling

- Don't catch `Exception` or `BaseException` without re-raising — catch specific exceptions
- Don't wrap every function call in try/except — let exceptions propagate to where they can be meaningfully handled
- Don't create custom exception hierarchies for internal code — use built-in exceptions (ValueError, TypeError, RuntimeError) with descriptive messages

## Imports

- Use absolute imports — relative imports (`from . import`) are harder to grep and refactor
- Don't create barrel modules (`__init__.py` that re-exports everything) until imports are genuinely painful
- Group imports: stdlib, third-party, local — but let ruff/isort handle the sorting

## Functions

- Return early for guard clauses — don't nest the happy path inside `if valid:`
- Don't use `*args, **kwargs` unless you're genuinely wrapping or forwarding — explicit parameters are self-documenting
- Don't add default arguments for values that are always passed by callers — defaults signal "optional"

## Testing

- Use `pytest` — don't use `unittest.TestCase` classes unless the project already does
- Don't create test base classes or fixtures for one-off setup — inline the setup in the test
- Don't mock what you can construct — if a function takes a dict, pass a dict, don't mock a dict
