#!/usr/bin/env bash
# docs_exports.sh — regenerate docs/drive-exports/ from docs/guides/.
# Run from the repo root after any guide change:  bash scripts/docs_exports.sh && node scripts/docs_guard.mjs
# Each export replaces one Drive document (see docs/drive-exports/README.md). Nothing is published by this script.
set -eu
cd "$(dirname "$0")/.."
mkdir -p docs/drive-exports
strip() { sed -E 's/\[([^]]+)\]\([^)]+\)/\1/g'; }
exp() { # out, title, Drive file replaced, pages...
  local out="docs/drive-exports/$1" title="$2" drv="$3"; shift 3
  {
    [ "${ALLOWB:-}" = 1 ] && printf '<!-- docs_guard: allow-banned -->\n'
    printf '# %s\n\n*Replacement text for the Drive file `%s`. Generated %s from docs/guides/; not published until the owner uploads it. Describes build: 2.5.10+%s.*\n\n' \
      "$title" "$drv" "$(date +%F)" "$(sed -nE 's/^version: [0-9.]+\+([0-9]+).*/\1/p' pubspec.yaml)"
    for p in "$@"; do printf '\n---\n\n'; strip < "$p"; done
  } > "$out"
}
C=docs/guides/customer; I=docs/guides/installer; D=docs/guides/dealer; N=docs/guides/internal
CUST=("$C"/00-getting-started.md "$C"/01-everyday-use.md "$C"/02-lumina-ai.md "$C"/03-scheduling.md "$C"/04-game-day.md "$C"/05-power-outage-and-recovery.md "$C"/06-troubleshooting.md "$C"/07-faq.md)
exp Lumina_Homeowner_Guide.md "Lumina Homeowner Guide" Lumina_Homeowner_Guide.pdf "${CUST[@]}"
exp User_Guide_Commercial.md "Lumina Commercial User Guide" User_Guide_Commercial.pdf "${CUST[@]}"
exp Dealer_Installer_Setup_Guide.md "Dealer and Installer Setup Guide" Dealer_Installer_Setup_Guide.pdf "$I"/10-install-checklist.md "$I"/11-controller-setup.md "$I"/12-bridge-guide.md "$I"/13-installer-sop.md
exp ESP32_Bridge_Setup_Guide.md "Lumina Bridge Setup" ESP32_Bridge_Setup_Guide.pdf "$I"/12-bridge-guide.md
exp day1-electrician-guide.md "Day 1 and Day 2 field guide" day1-electrician-guide.pdf "$D"/20-dealer-guide.md "$I"/10-install-checklist.md
exp day2-install-guide.md "Day 1 and Day 2 field guide" day2-install-guide.pdf "$D"/20-dealer-guide.md "$I"/10-install-checklist.md
exp Dealer_Dashboard_Guide.md "Dealer Guide" Dealer_Dashboard_Guide.pdf "$D"/20-dealer-guide.md
exp dealer-inventory-guide.md "Dealer Guide (inventory section)" dealer-inventory-guide.pdf "$D"/20-dealer-guide.md
exp messaging-configuration-guide.md "Dealer Guide (messaging section)" messaging-configuration-guide.pdf "$D"/20-dealer-guide.md
exp sales-mode-guide.md "Sales Mode Guide" sales-mode-guide.pdf "$D"/21-sales-mode.md
ALLOWB=1 exp Admin_Operations_Guide.md "Admin Operations Guide (internal)" Admin_Operations_Guide.pdf "$N"/30-admin-operations.md "$N"/33-claims-policy.md
ALLOWB=1 exp corporate-dashboard-guide.md "Admin Operations Guide (internal)" corporate-dashboard-guide.pdf "$N"/30-admin-operations.md
ALLOWB=1 exp nex-gen-operations-overview.md "Nex-Gen Lumina — how the guides fit together" nex-gen-operations-overview.pdf docs/guides/README.md "$N"/33-claims-policy.md
printf '# Media Mode Guide — withdrawn\n\n*Replacement for the Drive file `Media_Mode_Guide.pdf`. Not published.*\n\nMedia Mode has no entry point in the shipped app; nothing navigates to it. Pull the Drive PDF. If Media Mode ships later, a new page is written from `docs/FACTS.md` at that time.\n\n*Facts: T-X8.*\n' > docs/drive-exports/Media_Mode_Guide.md
echo "docs_exports: $(ls docs/drive-exports/*.md | wc -l) files in docs/drive-exports/"
