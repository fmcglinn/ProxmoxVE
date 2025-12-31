#!/usr/bin/env bash
# Copyright (c) 2021-2025 community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
#
# Validate that no remote code execution patterns exist in the repository
# Use as a git pre-commit hook to prevent accidental introduction of RCE
#
# Usage:
#   ./tools/validate-no-rce.sh           # Scan entire repo
#   ./tools/validate-no-rce.sh --staged  # Scan only staged files (for pre-commit)
#
# Exit codes:
#   0 - No unapproved RCE patterns found
#   1 - Unapproved RCE patterns detected
#
# Allowlist:
#   Add "# ALLOWED-RCE: <reason>" comment on the same line or the line before
#   to permit specific RCE patterns (e.g., third-party installers)
#
# Example:
#   # ALLOWED-RCE: Official Rust installer
#   curl -fsSL https://sh.rustup.rs | sh
#
#   curl -fsSL https://bun.sh/install | bash  # ALLOWED-RCE: Official Bun installer
#
# TODO: Improve pattern matching for edge cases

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Download tools that could be used for RCE
# This covers: curl, wget, fetch (BSD), aria2c, axel, httpie, lynx, etc.
DOWNLOAD_TOOLS='(curl|wget|fetch|aria2c|axel|http|lynx|ftp|nc|netcat)'

# RCE patterns to detect (actual code execution)
declare -a RCE_PATTERNS=(
  # Direct pipe to shell from any download tool
  "${DOWNLOAD_TOOLS}[^|]*\\|[^|]*\\b(bash|sh|zsh|ksh|dash|ash)\\b"

  # Process substitution with remote source (source/dot command)
  "source\\s*<\\s*\\(\\s*${DOWNLOAD_TOOLS}"
  "\\.\\s*<\\s*\\(\\s*${DOWNLOAD_TOOLS}"

  # Process substitution with direct shell execution: bash <(curl ...)
  "\\b(bash|sh|zsh|ksh|dash|ash)\\s+<\\s*\\(\\s*${DOWNLOAD_TOOLS}"
  "\\bSTD\\s+(bash|sh)\\s+<\\s*\\(\\s*${DOWNLOAD_TOOLS}"

  # Command substitution execution
  "bash\\s+-c\\s+\"\\$\\(${DOWNLOAD_TOOLS}"
  "sh\\s+-c\\s+\"\\$\\(${DOWNLOAD_TOOLS}"
  "zsh\\s+-c\\s+\"\\$\\(${DOWNLOAD_TOOLS}"

  # eval with remote content
  "eval\\s+\"\\$\\(${DOWNLOAD_TOOLS}"
  "eval\\s+'\\$\\(${DOWNLOAD_TOOLS}"
  # eval with variable assignment from remote: eval "$var=$(curl ...)"
  'eval\s+"\$[a-zA-Z_][a-zA-Z0-9_]*=\$\((curl|wget|fetch|aria2c|axel|http|lynx|ftp|nc|netcat)'

  # Direct execution of downloaded content via stdin
  "/dev/stdin\\s*<<<.*${DOWNLOAD_TOOLS}"

  # Python-based remote execution
  'python[23]?\s+-c\s+.*urllib'
  'python[23]?\s+-c\s+.*requests'
  'python[23]?\s+-c\s+.*http\.client'

  # Ruby-based remote execution
  'ruby\s+-e\s+.*open-uri'
  'ruby\s+-e\s+.*Net::HTTP'

  # Perl-based remote execution
  'perl\s+-e\s+.*LWP'
  'perl\s+-e\s+.*HTTP'
  'perl\s+-M.*http'

  # PHP-based remote execution
  'php\s+-r\s+.*file_get_contents.*http'
  'php\s+-r\s+.*curl_exec'

  # Node.js-based remote execution
  'node\s+-e\s+.*https?\.(get|request)'

  # PowerShell (if running on Windows/cross-platform)
  'pwsh.*Invoke-WebRequest.*\|'
  'pwsh.*Invoke-RestMethod.*\|'
  'powershell.*Invoke-WebRequest.*\|'
  'powershell.*Invoke-RestMethod.*\|'
  'IEX.*\(.*WebRequest'
  'iex.*\(.*WebRequest'
)

# Patterns that look like RCE but are actually safe (data processing, not execution)
declare -a SAFE_PATTERNS=(
  '\|\s*gpg'           # GPG key imports
  '\|\s*jq'            # JSON parsing
  '\|\s*tee\s'         # Writing to file (not executing)
  '\|\s*tar\s'         # Archive extraction
  '\|\s*gzip'          # Compression
  '\|\s*gunzip'        # Decompression
  '\|\s*base64'        # Encoding/decoding
  '\|\s*openssl'       # Certificate/crypto operations
  '\|\s*sha[0-9]*sum'  # Checksum verification
  '\|\s*md5sum'        # Checksum verification
  '\|\s*cat\s'         # Concatenation
  '\|\s*head\s'        # Reading first lines
  '\|\s*tail\s'        # Reading last lines
  '\|\s*grep\s'        # Pattern matching
  '\|\s*sed\s'         # Stream editing
  '\|\s*awk\s'         # Text processing
  '\|\s*cut\s'         # Column extraction
  '\|\s*tr\s'          # Character translation
  '\|\s*sort\s'        # Sorting
  '\|\s*uniq\s'        # Deduplication
  '\|\s*wc\s'          # Word/line counting
  '\|\s*xargs\s'       # Argument building (careful, but usually safe)
  '\|\s*install\s+-'   # install command for file placement
)

# Files/patterns to exclude from scanning
declare -a EXCLUDE_PATTERNS=(
  '\.git/'
  '\.github/'  # CI/CD workflows (expected to have remote execution)
  'validate-no-rce\.sh'  # This script itself
  'node_modules/'
  '\.md$'  # Documentation files
  'CHANGELOG'
  'LICENSE'
)

violations=0
allowed_count=0
scanned=0

# Arrays to store results for reporting
declare -a violation_list=()
declare -a allowed_list=()

# Check if file should be excluded
should_exclude() {
  local file="$1"
  for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    if [[ "$file" =~ $pattern ]]; then
      return 0
    fi
  done
  return 1
}

# Check if a line matches safe patterns (not actually RCE)
is_safe_pattern() {
  local content="$1"
  for safe in "${SAFE_PATTERNS[@]}"; do
    if [[ "$content" =~ $safe ]]; then
      return 0
    fi
  done
  return 1
}

# Check if a line is allowed via ALLOWED-RCE comment
# Checks both the current line and the previous line
is_allowed_rce() {
  local file="$1"
  local line_num="$2"
  local content="$3"

  # Check if current line has ALLOWED-RCE comment
  if [[ "$content" =~ ALLOWED-RCE: ]]; then
    return 0
  fi

  # Check if previous line has ALLOWED-RCE comment
  if [[ $line_num -gt 1 ]]; then
    local prev_line
    prev_line=$(sed -n "$((line_num - 1))p" "$file" 2>/dev/null || true)
    if [[ "$prev_line" =~ ALLOWED-RCE: ]]; then
      return 0
    fi
  fi

  return 1
}

# Extract the ALLOWED-RCE reason
get_allowed_reason() {
  local file="$1"
  local line_num="$2"
  local content="$3"

  # Check current line first
  if [[ "$content" =~ ALLOWED-RCE:(.*)$ ]]; then
    echo "${BASH_REMATCH[1]}" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'
    return
  fi

  # Check previous line
  if [[ $line_num -gt 1 ]]; then
    local prev_line
    prev_line=$(sed -n "$((line_num - 1))p" "$file" 2>/dev/null || true)
    if [[ "$prev_line" =~ ALLOWED-RCE:(.*)$ ]]; then
      echo "${BASH_REMATCH[1]}" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'
      return
    fi
  fi

  echo "No reason provided"
}

# Scan a single file for RCE patterns
scan_file() {
  local file="$1"
  local file_violations=0
  local file_allowed=0
  local relative_file="${file#$REPO_ROOT/}"

  # Skip excluded files
  if should_exclude "$file"; then
    return 0
  fi

  # Skip non-existent files (deleted in staging)
  [[ -f "$file" ]] || return 0

  # Skip binary files
  if file "$file" 2>/dev/null | grep -q "binary"; then
    return 0
  fi

  ((scanned++)) || true

  for pattern in "${RCE_PATTERNS[@]}"; do
    local matches
    matches=$(grep -nE "$pattern" "$file" 2>/dev/null || true)

    if [[ -n "$matches" ]]; then
      while IFS= read -r match; do
        [[ -z "$match" ]] && continue

        local line_num="${match%%:*}"
        local content="${match#*:}"

        # Skip pure comment lines (but not if checking for ALLOWED-RCE)
        if [[ "$content" =~ ^[[:space:]]*# ]] && [[ ! "$content" =~ ALLOWED-RCE ]]; then
          continue
        fi

        # Skip safe patterns (gpg, jq, etc.)
        if is_safe_pattern "$content"; then
          continue
        fi

        # Check if this RCE is explicitly allowed
        if is_allowed_rce "$file" "$line_num" "$content"; then
          local reason
          reason=$(get_allowed_reason "$file" "$line_num" "$content")
          allowed_list+=("${relative_file}:${line_num}|${reason}|${content}")
          ((allowed_count++)) || true
          ((file_allowed++)) || true
        else
          if [[ $file_violations -eq 0 ]]; then
            echo -e "${RED}[RCE DETECTED]${NC} $relative_file"
          fi
          echo -e "  ${YELLOW}Line $line_num:${NC} $content"
          violation_list+=("${relative_file}:${line_num}|${content}")
          ((violations++)) || true
          ((file_violations++)) || true
        fi
      done <<< "$matches"
    fi
  done

  return 0
}

# Print allowed RCE report
print_allowed_report() {
  if [[ ${#allowed_list[@]} -eq 0 ]]; then
    return
  fi

  echo ""
  echo -e "${CYAN}=== Allowed RCE Report ===${NC}"
  echo ""

  local current_file=""
  for entry in "${allowed_list[@]}"; do
    local file_line="${entry%%|*}"
    local rest="${entry#*|}"
    local reason="${rest%%|*}"
    local content="${rest#*|}"
    local file="${file_line%%:*}"
    local line="${file_line#*:}"

    if [[ "$file" != "$current_file" ]]; then
      current_file="$file"
      echo -e "${BLUE}[ALLOWED]${NC} $file"
    fi
    echo -e "  ${YELLOW}Line $line:${NC} $content"
    echo -e "  ${GREEN}Reason:${NC} $reason"
  done
}

# Main scanning logic
main() {
  local mode="all"

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --staged)
        mode="staged"
        shift
        ;;
      --help|-h)
        echo "Usage: $0 [--staged]"
        echo ""
        echo "Options:"
        echo "  --staged    Only scan staged files (for pre-commit hook)"
        echo "  --help      Show this help message"
        echo ""
        echo "Allowlist:"
        echo "  Add '# ALLOWED-RCE: <reason>' comment on the same line or line before"
        echo "  to permit specific RCE patterns (e.g., third-party installers)"
        echo ""
        echo "Download tools detected: curl, wget, fetch, aria2c, axel, httpie, lynx, ftp, nc"
        echo "Also detects: Python/Ruby/Perl/PHP/Node.js remote execution patterns"
        exit 0
        ;;
      *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
  done

  echo "=== Remote Code Execution Validation ==="
  echo ""

  cd "$REPO_ROOT"

  if [[ "$mode" == "staged" ]]; then
    echo "Scanning staged files..."
    echo ""

    # Get list of staged files
    while IFS= read -r file; do
      [[ -n "$file" ]] && scan_file "$REPO_ROOT/$file"
    done < <(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)
  else
    echo "Scanning entire repository..."
    echo ""

    # Scan all shell scripts and function files
    while IFS= read -r file; do
      scan_file "$file"
    done < <(find "$REPO_ROOT" \( -name "*.sh" -o -name "*.func" \) -type f 2>/dev/null)
  fi

  # Print allowed RCE report
  print_allowed_report

  echo ""
  echo "=== Summary ==="
  echo "Files scanned: $scanned"
  echo -e "Allowed RCE (with reason): ${BLUE}$allowed_count${NC}"

  if [[ $violations -gt 0 ]]; then
    echo -e "${RED}Unapproved RCE violations: $violations${NC}"
    echo ""
    echo "To fix violations, either:"
    echo "  1. Replace remote source with local file path"
    echo "  2. Add '# ALLOWED-RCE: <reason>' comment to permit (for third-party installers)"
    exit 1
  else
    echo -e "${GREEN}No unapproved RCE patterns detected${NC}"
    exit 0
  fi
}

main "$@"
