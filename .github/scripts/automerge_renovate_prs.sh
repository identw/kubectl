#!/usr/bin/env bash
# Validate and automerge bot PRs:
# - renovate/* : alpine and/or kubectl version bumps in existing Dockerfile_v*.x
# - chore/new-kubectl-minor-* : new Dockerfile_v*.x matching the shared template
# Prints one line per merged PR: MERGED <pr> kubectl=<ver|ver,ver|none> alpine=<yes|no>
set -euo pipefail

REPO="${REPO:?REPO is required}"
GH_TOKEN="${GH_TOKEN:?GH_TOKEN is required}"
export GH_TOKEN

pr_list="$(gh api "repos/${REPO}/pulls?state=open&per_page=100" --paginate)"

pr_numbers="$(PR_LIST_JSON="$pr_list" python3 -c '
import json, os
prs = json.loads(os.environ["PR_LIST_JSON"])
for pr in prs:
    user = (pr.get("user") or {}).get("login") or ""
    head_ref = ((pr.get("head") or {}).get("ref") or "")
    draft = pr.get("draft", False)
    if user != "github-actions[bot]" or draft:
        continue
    if head_ref.startswith("renovate/") or head_ref.startswith("chore/new-kubectl-minor-"):
        print(pr["number"])
')"

if [ -z "${pr_numbers}" ]; then
  echo "No eligible bot PRs"
  exit 0
fi

validate_py='
import json, os, re
from pathlib import Path

ALPINE_RE = re.compile(r"^[-+]FROM docker\.io/alpine:\d+\.\d+\.\d+\s*$")
KUBECTL_RE = re.compile(
    r"^[-+].*https://dl\.k8s\.io/release/v\d+\.\d+\.\d+/bin/linux/amd64/kubectl.*$"
)
KUBECTL_PLUS = re.compile(
    r"^\+.*https://dl\.k8s\.io/release/(v\d+\.\d+\.\d+)/bin/linux/amd64/kubectl"
)
KUBECTL_IN_FILE = re.compile(
    r"https://dl\.k8s\.io/release/(v\d+\.\d+\.\d+)/bin/linux/amd64/kubectl"
)
DOCKERFILE_RE = re.compile(r"^Dockerfile_v(\d+)\.(\d+)\.x$")

def normalize(text: str) -> str:
    text = re.sub(
        r"FROM docker\.io/alpine:\d+\.\d+\.\d+",
        "FROM docker.io/alpine:__ALPINE__",
        text,
    )
    text = re.sub(
        r"https://dl\.k8s\.io/release/v\d+\.\d+\.\d+/bin/linux/amd64/kubectl",
        "https://dl.k8s.io/release/v__KUBECTL__/bin/linux/amd64/kubectl",
        text,
    )
    return text

def content_from_added_patch(patch: str) -> str:
    lines = []
    for line in patch.splitlines():
        if line.startswith("+++") or line.startswith("---"):
            continue
        if line.startswith("+"):
            lines.append(line[1:])
        elif line.startswith("-"):
            raise ValueError("unexpected deleted line in added file patch")
        elif line.startswith(" "):
            lines.append(line[1:])
    body = "\n".join(lines)
    if body and not body.endswith("\n"):
        body += "\n"
    return body

def load_reference_normalized() -> str:
    refs = sorted(Path(".").glob("Dockerfile_v*.x"))
    if not refs:
        raise SystemExit("REJECT:no-reference-dockerfile")
    return normalize(refs[-1].read_text())

files = json.loads(os.environ["FILES_JSON"])
if not files:
    print("REJECT:no-files")
    raise SystemExit(0)

kubectl_versions = []
alpine_changed = False
ref_norm = None

for f in files:
    name = f.get("filename", "")
    status = f.get("status", "")
    patch = f.get("patch") or ""

    if status in ("removed", "renamed"):
        print(f"REJECT:status:{name}:{status}")
        raise SystemExit(0)
    if not DOCKERFILE_RE.match(name):
        print(f"REJECT:file:{name}")
        raise SystemExit(0)
    if not patch:
        print(f"REJECT:empty-patch:{name}")
        raise SystemExit(0)

    if status == "added":
        m = DOCKERFILE_RE.match(name)
        major, minor = m.group(1), m.group(2)
        try:
            content = content_from_added_patch(patch)
        except ValueError as exc:
            print(f"REJECT:added-patch:{name}:{exc}")
            raise SystemExit(0)

        km = KUBECTL_IN_FILE.search(content)
        if not km:
            print(f"REJECT:added-no-kubectl:{name}")
            raise SystemExit(0)
        version = km.group(1)
        if not version.startswith(f"v{major}.{minor}."):
            print(f"REJECT:added-version-mismatch:{name}:{version}")
            raise SystemExit(0)

        if ref_norm is None:
            ref_norm = load_reference_normalized()
        if normalize(content) != ref_norm:
            print(f"REJECT:added-template-mismatch:{name}")
            raise SystemExit(0)

        kubectl_versions.append(version)
        continue

    # modified existing Dockerfile: only alpine/kubectl version lines
    for line in patch.splitlines():
        if not (line.startswith("+") or line.startswith("-")):
            continue
        if line.startswith("+++") or line.startswith("---"):
            continue
        if ALPINE_RE.match(line):
            if line.startswith("+"):
                alpine_changed = True
            continue
        if KUBECTL_RE.match(line):
            m = KUBECTL_PLUS.match(line)
            if m:
                kubectl_versions.append(m.group(1))
            continue
        print(f"REJECT:line:{name}:{line}")
        raise SystemExit(0)

# one kubectl version per affected file is fine; dedupe for output
unique = []
for v in kubectl_versions:
    if v not in unique:
        unique.append(v)

kubectl = ",".join(unique) if unique else "none"
alpine = "yes" if alpine_changed else "no"
print(f"OK kubectl={kubectl} alpine={alpine}")
'

while IFS= read -r PR_NUMBER; do
  [ -n "${PR_NUMBER}" ] || continue
  files_json="$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/files" --paginate)"
  result="$(FILES_JSON="$files_json" python3 -c "${validate_py}")"

  if [[ "${result}" != OK* ]]; then
    echo "PR #${PR_NUMBER}: skip (${result})"
    continue
  fi

  echo "PR #${PR_NUMBER}: ${result} - merging"
  if ! gh pr merge "${PR_NUMBER}" --repo "${REPO}" --merge --delete-branch; then
    echo "PR #${PR_NUMBER}: merge failed (checks pending?)"
    continue
  fi

  echo "MERGED ${PR_NUMBER} ${result#OK }"
done <<< "${pr_numbers}"
