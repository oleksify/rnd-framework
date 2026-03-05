---
name: prefer-system-tools
description: Use when about to write a helper script — check if a native CLI tool can do it directly before reaching for Bun or Python
---

# Prefer System Tools Over Scripts

Before writing a Python or Bun script for a common task, check if a native CLI tool can do it directly. Single-purpose tools are faster, more reliable, and require no runtime. Use scripts only when the task involves **multi-step logic, conditionals, or data transformation that combines several operations**.

## Rules

1. **Only use tools already installed on the system.** Check with `command -v <tool>` before using.
2. **Never install tools via npm, npx, bunx, or any JavaScript package manager.** All tools referenced here are standalone system binaries — install them via the OS package manager (`apt`, `brew`, `pacman`, etc.) or not at all.
3. If a preferred tool is not available, fall back to the POSIX alternative listed, or write a short Bun/Python script instead.

## JSON Processing

**Instead of** writing a script with `json.loads()` / `JSON.parse()`, use `jq`:

```bash
# Extract a field
jq '.name' config.json

# Filter an array
jq '.users[] | select(.age > 30)' data.json

# Transform structure
jq '{ids: [.items[].id], count: (.items | length)}' data.json

# Process NDJSON / JSON lines
jq -c 'select(.level == "error")' events.jsonl

# Modify in place (via sponge or temp file)
jq '.version = "2.0"' package.json | sponge package.json
```

`jq` handles nested access, filtering, mapping, grouping, and formatting — this covers 90% of cases where agents write JSON scripts.

## YAML Processing

**Instead of** `import yaml` / a YAML npm package, use `yq`:

```bash
# Read a value
yq '.services.web.image' docker-compose.yml

# Convert YAML to JSON
yq -o=json '.' config.yaml

# Update a value
yq -i '.spec.replicas = 3' deployment.yaml

# Merge files
yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' base.yaml override.yaml
```

## CSV / TSV Processing

**Instead of** `import csv` / `pandas.read_csv()`, use standard tools for simple operations:

```bash
# Extract columns (cut)
cut -d',' -f1,3 data.csv

# Filter rows (awk)
awk -F',' '$3 > 100 {print $1, $3}' data.csv

# Sort by column
sort -t',' -k2 -n data.csv

# Deduplicate
sort -u data.csv

# Count occurrences of a field
cut -d',' -f2 data.csv | sort | uniq -c | sort -rn

# Pretty-print CSV as table
column -t -s',' data.csv
```

For more complex CSV work (joins, aggregations, SQL-like queries), use `csvq` or `xsv`:

```bash
# xsv: fast Rust-based CSV toolkit
xsv select name,age data.csv
xsv search -s status "active" data.csv
xsv stats data.csv
xsv join --left id users.csv user_id orders.csv

# csvq: SQL queries on CSV
csvq "SELECT name, COUNT(*) FROM data.csv GROUP BY name"
```

## XML / HTML Processing

**Instead of** `from lxml import etree` / `BeautifulSoup`, use `xmlstarlet` or `xq` (part of yq):

```bash
# Extract with xpath
xmlstarlet sel -t -v "//item/title" feed.xml

# HTML extraction (using xq from yq package, or pup)
curl -s https://example.com | pup 'h1 text{}'
curl -s https://example.com | pup 'a[href] attr{href}'
```

## HTTP Requests

**Instead of** `requests.get()` / `fetch()`, use `curl` or `httpie`:

```bash
# GET with headers
curl -s -H "Authorization: Bearer $TOKEN" https://api.example.com/data

# POST JSON
curl -s -X POST https://api.example.com/submit \
  -H "Content-Type: application/json" \
  -d '{"key": "value"}'

# Download file
curl -Lo output.zip https://example.com/file.zip

# httpie (more readable, if available)
http GET api.example.com/data Authorization:"Bearer $TOKEN"
http POST api.example.com/submit key=value
```

## File Search and Manipulation

**Instead of** `os.walk()` / `glob.glob()` / `pathlib.rglob()`:

**Primary approach — `fd` and Claude Code's Glob tool:**

```bash
# fd (Rust-based, respects .gitignore, fast)
fd '\.ts$' src/
fd -e json -x jq '.version' {}
fd -t f -e py src/            # files only
```

Or use the **Glob tool** in Claude Code for file pattern matching — it's reviewable, needs no shell, and works on any codebase size.

**POSIX fallback — `find`:**

> **Note:** `find`, `grep`, and `sed` are blocked by the `prefer-tools` hook in pipeline sessions. Use `fd`/`rg`/`sd` or Claude Code's Glob/Grep/Edit tools instead.

```bash
# find: use only when fd is unavailable
find . -name "*.py" -type f
find . -name "*.pyc" -delete
find . -name "*.log" -mtime +30 -delete
```

**Bulk rename:**

```bash
rename 's/\.jpeg$/.jpg/' *.jpeg        # perl-rename
for f in *.jpeg; do mv "$f" "${f%.jpeg}.jpg"; done  # bash fallback
```

## Text Search

**Instead of** writing regex scripts with `re.findall()`:

**Primary approach — `rg` and Claude Code's Grep tool:**

```bash
# ripgrep (rg) — fast, respects .gitignore
rg "TODO" --type py
rg -l "deprecated" --type ts          # list files only
rg "fn\s+\w+" --type rust -c          # count matches per file
```

Or use the **Grep tool** in Claude Code — same power as rg, no shell needed.

**Search and replace — `sd` (primary) or Claude Code's Edit tool:**

```bash
# sd: Rust-based, simpler syntax than sed
sd 'oldPattern' 'newPattern' src/**/*.ts
```

**POSIX fallback — `grep` / `sed`:**

> **Note:** `find`, `grep`, and `sed` are blocked by the `prefer-tools` hook in pipeline sessions. Use `fd`/`rg`/`sd` or Claude Code's Glob/Grep/Edit tools instead.

```bash
# grep/sed: use only when rg/sd are unavailable
grep -rn "TODO" --include="*.py" ./src
sed -i 's/old_name/new_name/g' src/*.py
```

## File Diffing and Comparison

**Instead of** `difflib` scripts:

```bash
# Standard diff
diff -u file1.txt file2.txt

# Side-by-side
diff -y file1.txt file2.txt

# Colored diff (delta, if available)
diff -u a.txt b.txt | delta

# Compare directories
diff -rq dir1/ dir2/

# Compare JSON specifically
diff <(jq -S '.' a.json) <(jq -S '.' b.json)
```

## Checksums and Hashing

**Instead of** `hashlib.sha256()`:

```bash
sha256sum file.txt
md5sum file.txt
b2sum file.txt                         # blake2

# Verify
echo "expected_hash  file.txt" | sha256sum -c

# Hash a string
echo -n "content" | sha256sum
```

## Date and Time

**Instead of** `datetime.now()` / `timedelta` scripts:

```bash
# Current timestamp
date +%Y-%m-%dT%H:%M:%S%z

# Epoch seconds
date +%s

# Convert epoch to human-readable
date -d @1700000000

# Date arithmetic
date -d "+7 days" +%Y-%m-%d
date -d "2024-01-15 + 3 months" +%Y-%m-%d
```

## Encoding and Decoding

**Instead of** `base64` / `urllib.parse` scripts:

```bash
# Base64
echo -n "hello" | base64
echo "aGVsbG8=" | base64 -d

# URL encode/decode
printf '%s' "hello world" | jq -sRr @uri
printf '%b' "$(echo 'hello%20world' | sed 's/%/\\x/g')"

# Hex
echo -n "hello" | xxd -p
echo "68656c6c6f" | xxd -r -p
```

## Process and System Info

**Instead of** `psutil` / `subprocess` wrappers:

```bash
# Disk usage
df -h
du -sh /path/to/dir
du -sh */ | sort -rh | head -20       # largest subdirs

# Memory
free -h

# Process listing
ps aux --sort=-%mem | head -20
pgrep -af "pattern"

# Port usage
ss -tlnp                               # or: lsof -i :8080

# Watch for changes
watch -n 2 'df -h /'
```

## Archive and Compression

**Instead of** `zipfile` / `tarfile` / `shutil` scripts:

```bash
# Create archives
tar czf archive.tar.gz ./directory
zip -r archive.zip ./directory

# Extract
tar xzf archive.tar.gz
unzip archive.zip -d output/

# List contents without extracting
tar tzf archive.tar.gz
unzip -l archive.zip

# Compress single file
gzip file.txt                          # produces file.txt.gz
zstd file.txt                          # faster, better ratio
```

## Sorting, Deduplication, and Counting

**Instead of** `collections.Counter` / set operations:

```bash
# Top 10 most frequent lines
sort file.txt | uniq -c | sort -rn | head -10

# Unique lines preserving order
awk '!seen[$0]++' file.txt

# Set operations on sorted files
comm -12 sorted1.txt sorted2.txt       # intersection
comm -23 sorted1.txt sorted2.txt       # in 1 but not 2
comm -13 sorted1.txt sorted2.txt       # in 2 but not 1

# Line count, word count
wc -l file.txt
wc -w file.txt
```

## String Templating

**Instead of** writing a Python script with f-strings or `.format()`:

```bash
# envsubst: substitute environment variables in templates
export NAME="world" PORT=8080
envsubst < template.conf > output.conf

# Where template.conf contains:
# server_name $NAME;
# listen $PORT;
```

## Image Processing (when simple)

**Instead of** Pillow for basic operations:

```bash
# ImageMagick (convert/magick)
magick input.png -resize 50% output.png
magick input.png -quality 80 output.jpg
magick *.jpg -append combined.png       # vertical stack
magick identify image.png               # get dimensions/metadata

# FFmpeg for video/audio (and some image tasks)
ffmpeg -i video.mp4 -ss 00:01:00 -frames:v 1 thumbnail.jpg
```

## Decision Guide

| Task | Use Tool | Write Script |
|---|---|---|
| Extract a JSON field | `jq` | -- |
| Filter + transform + merge JSON | `jq` if expressible | Script if logic is complex |
| Single HTTP request | `curl` | -- |
| HTTP with retry logic, auth flows, pagination | -- | Script |
| Find files by name/pattern | `fd` / Glob tool | -- |
| Find files + process each with custom logic | -- | Script |
| Search text in files | `rg` / `grep` | -- |
| Search + complex replacement with context | -- | Script |
| Simple CSV column extraction | `cut` / `awk` | -- |
| CSV joins, pivots, multi-step transforms | -- | Script |
| Compute a hash | `sha256sum` | -- |
| String encode/decode | `base64` / `xxd` | -- |
| Multi-step workflow with conditionals | -- | Script |
| Coordinate several tools with error handling | -- | Script |

The rule of thumb: **if the task can be expressed as a single pipeline of 1-3 commands, use CLI tools. If it needs branching, loops over structured data, or error recovery, write a script.**
