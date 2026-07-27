#!/usr/bin/env bash
#
# Copyright 2026 Jason Jamieson
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Copies AGENTS.md over the tool-specific instruction files.
#
#   scripts/sync-agent-docs.sh           # write the mirrors
#   scripts/sync-agent-docs.sh --check   # exit non-zero if any mirror is stale
#
# The same check runs in CI. Install the pre-commit hook to catch it earlier:
#
#   git config core.hooksPath .githooks

set -euo pipefail

cd "$(dirname "$0")/.."

CANONICAL="AGENTS.md"
MIRRORS=(
  "CLAUDE.md"
  "GEMINI.md"
  ".junie/guidelines.md"
  ".github/copilot-instructions.md"
)

if [ ! -f "$CANONICAL" ]; then
  echo "error: $CANONICAL not found" >&2
  exit 1
fi

if [ "${1:-}" = "--check" ]; then
  status=0
  for mirror in "${MIRRORS[@]}"; do
    if ! cmp -s "$CANONICAL" "$mirror"; then
      echo "error: $mirror differs from $CANONICAL" >&2
      status=1
    fi
  done
  if [ "$status" -ne 0 ]; then
    echo "run: scripts/sync-agent-docs.sh" >&2
  fi
  exit "$status"
fi

for mirror in "${MIRRORS[@]}"; do
  mkdir -p "$(dirname "$mirror")"
  cp "$CANONICAL" "$mirror"
  echo "synced $mirror"
done
