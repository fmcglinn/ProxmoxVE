#!/usr/bin/env bash
# Copyright (c) 2021-2025 community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
#
# Transform scripts for offline/local operation:
# 1. CT scripts: Use local sourcing instead of remote GitHub sources
# 2. VM scripts: Standardize descriptions to plain text (remove external URLs)
# 3. build.func: Already handled separately
#
# This enables offline operation of the ProxmoxVE helper scripts

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== ProxmoxVE Script Localization ==="
echo ""
echo "Repo root: ${REPO_ROOT}"
echo ""

# Counters
transformed=0
skipped=0
errors=0
vm_transformed=0

# Process all CT scripts
for script in "${REPO_ROOT}/ct/"*.sh; do
  [[ -f "$script" ]] || continue

  filename=$(basename "$script")

  # Check if already transformed (look for SCRIPT_DIR pattern)
  if grep -q 'SCRIPT_DIR=.*dirname.*BASH_SOURCE' "$script" 2>/dev/null; then
    echo "  [SKIP] ${filename} (already transformed)"
    ((skipped++)) || true
    continue
  fi

  # Check if it has any remote source pattern for build.func
  if ! grep -qE 'source <\(curl.*misc/build\.func\)' "$script" 2>/dev/null; then
    echo "  [WARN] ${filename} (no remote source pattern found, skipping)"
    ((skipped++)) || true
    continue
  fi

  # Transform the script - handle multiple URL variants
  # Patterns: curl -s, curl -fsSL, refs/heads/main, main, etc.
  if sed -i -E 's|source <\(curl[^)]*github[^)]*misc/build\.func\)|SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." \&\& pwd)"\nsource "${SCRIPT_DIR}/misc/build.func"|' "$script" 2>/dev/null; then
    echo "  [OK]   ${filename}"
    ((transformed++)) || true
  else
    echo "  [ERR]  ${filename} (sed failed)"
    ((errors++)) || true
  fi
done

echo ""
echo "=== CT Script Summary ==="
echo "  Transformed: ${transformed}"
echo "  Skipped:     ${skipped}"
echo "  Errors:      ${errors}"
echo ""

# ==============================================================================
# PHASE 2: INSTALL SCRIPT TRANSFORMATION
# ==============================================================================
echo "=== Install Script Transformation ==="
echo ""

install_transformed=0
install_skipped=0

# Process all install scripts
for script in "${REPO_ROOT}/install/"*.sh; do
  [[ -f "$script" ]] || continue

  filename=$(basename "$script")

  # Check if already transformed (no stdin pattern)
  if ! grep -q 'source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"' "$script" 2>/dev/null; then
    echo "  [SKIP] ${filename} (already transformed or no pattern)"
    ((install_skipped++)) || true
    continue
  fi

  # Transform: source from stdin to direct file source
  if sed -i 's|source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"|source "$FUNCTIONS_FILE_PATH"|' "$script" 2>/dev/null; then
    echo "  [OK]   ${filename}"
    ((install_transformed++)) || true
  else
    echo "  [ERR]  ${filename} (sed failed)"
    ((errors++)) || true
  fi
done

echo ""
echo "=== Install Script Summary ==="
echo "  Transformed: ${install_transformed}"
echo "  Skipped:     ${install_skipped}"
echo ""

# ==============================================================================
# PHASE 3: VM DESCRIPTION TRANSFORMATION
# ==============================================================================
echo "=== VM Description Transformation ==="
echo ""

# Function to transform VM description to plain text
transform_vm_description() {
  local script="$1"
  local filename=$(basename "$script")

  # Extract the VM name from the script (usually in the filename or DESCRIPTION)
  local vm_name="${filename%.sh}"
  vm_name="${vm_name//-/ }"  # Replace hyphens with spaces
  vm_name="${vm_name^}"       # Capitalize first letter

  # Check if script has the HTML description pattern
  if ! grep -q "DESCRIPTION=\$(" "$script" 2>/dev/null; then
    return 1  # No description block found
  fi

  # Check if already transformed (plain text description)
  if grep -q 'DESCRIPTION=".*VM - Created' "$script" 2>/dev/null; then
    return 2  # Already transformed
  fi

  # Create a temporary file for the transformation
  local tmpfile=$(mktemp)

  # Use awk to replace the multi-line DESCRIPTION block
  awk '
    /^DESCRIPTION=\$\(/ {
      # Found start of DESCRIPTION block, skip until EOF
      in_desc = 1
      # Print the replacement
      print "# VM Description (plain text for security)"
      print "DESCRIPTION=\"${HN} VM - Created $(date +%Y-%m-%d)\""
      next
    }
    in_desc && /^EOF$/ {
      # Found end of DESCRIPTION block
      in_desc = 0
      getline  # Skip the closing )
      next
    }
    in_desc && /^\)$/ {
      # Alternative: closing ) on its own line
      in_desc = 0
      next
    }
    !in_desc {
      print
    }
  ' "$script" > "$tmpfile"

  # Replace original file
  mv "$tmpfile" "$script"
  return 0
}

# Process all VM scripts
for script in "${REPO_ROOT}/vm/"*.sh; do
  [[ -f "$script" ]] || continue

  filename=$(basename "$script")

  transform_vm_description "$script"
  result=$?

  case $result in
    0)
      echo "  [OK]   ${filename}"
      ((vm_transformed++)) || true
      ;;
    1)
      echo "  [SKIP] ${filename} (no description block)"
      ;;
    2)
      echo "  [SKIP] ${filename} (already transformed)"
      ;;
  esac
done

echo ""
echo "=== VM Summary ==="
echo "  Transformed: ${vm_transformed}"
echo ""

# ==============================================================================
# FINAL SUMMARY
# ==============================================================================
echo "=== Final Summary ==="
echo "  CT scripts transformed:      ${transformed}"
echo "  Install scripts transformed: ${install_transformed}"
echo "  VM scripts transformed:      ${vm_transformed}"
echo "  Errors:                      ${errors}"
echo ""

if [[ $errors -gt 0 ]]; then
  echo "Some scripts failed to transform. Please check manually."
  exit 1
fi

echo "Done."
