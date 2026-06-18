#!/bin/zsh
# =============================================================================
# Repo-Wartung – gemergte Branches loeschen (KommunalBIT)
#
# SPDX-License-Identifier: EUPL-1.2
# Licensed under the EUPL, Version 1.2
#
# Zweck:
#   Loescht eine fest definierte Liste von Remote-Branches, deren zugehoerige
#   Pull Requests bereits in main gemergt wurden (per Squash-Merge, daher
#   nicht ueber `git branch -r --merged` erkennbar).
#
# Geltungsbereich:
#   Reines Repository-Wartungswerkzeug. KEIN Bestandteil der AssetCache-
#   Messpipeline. Nicht in deploy/uninstall/archive einbinden.
#
# Voraussetzungen:
#   - Lokales Clone mit Push-Recht auf origin (z. B. Admin-Workstation).
#   - main, master und nicht gemergte Branches werden NICHT angefasst.
# =============================================================================

set -u

BRANCHES=(
  "Jens-Siegfried-patch-1"
  "claude/add-asset-cache-csv-export-DDpSw"
  "claude/add-claude-documentation-7QUSR"
  "claude/add-data-minimization-docs-XtDqh"
  "claude/add-datenmodell-to-copilot-prompt"
  "claude/add-relution-export-cleaner-1IaxC"
  "claude/analyze-caching-server-ZrZMk"
  "claude/extract-scripts-restructure-howtoCopilot"
  "claude/fix-readme-table-howtoCopilot-title"
  "claude/format-license-dudcv"
  "claude/license-en-de"
  "claude/prompt-exploratory-phase"
  "claude/raw-first-pipeline-v1.8.0-zxIon"
  "claude/refine-copilot-prompt-0Y95w"
  "claude/refine-copilot-prompt-okVy9"
  "claude/spdx-license-fix"
  "claude/translate-changelog-de"
  "claude/update-readme-structure-2SV5A"
  "claude/update-version-1-7-0-JJJUf"
  "codex/add-codex-as-contributor"
  "codex/add-codex-as-contributor-phk8kn"
  "codex/bewerte-dieses-repo"
  "codex/update-documentation-in-assetcache_monitoring.md"
)

REMOTE="${1:-origin}"

print "Remote: ${REMOTE}"
print "Zu loeschende Branches: ${#BRANCHES[@]}"
print ""

git fetch --prune "${REMOTE}"

failed=()
for b in "${BRANCHES[@]}"; do
  print "--> ${b}"
  if git push "${REMOTE}" --delete "${b}"; then
    print "    geloescht"
  else
    print "    FEHLER (uebersprungen)"
    failed+=("${b}")
  fi
done

print ""
if (( ${#failed[@]} == 0 )); then
  print "Alle Branches erfolgreich geloescht."
else
  print "Fehlgeschlagen (${#failed[@]}):"
  for b in "${failed[@]}"; do
    print "  - ${b}"
  done
  exit 1
fi
