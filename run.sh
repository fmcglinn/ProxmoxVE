#!/usr/bin/env bash
# ProxmoxVE Script Launcher - Interactive discovery and installation
# Copyright (c) 2021-2025 community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
JSON_DIR="${SCRIPT_DIR}/frontend/public/json"
METADATA_FILE="${JSON_DIR}/metadata.json"

# Colors
RD="\033[01;31m"
GN="\033[1;92m"
YW="\033[33m"
CL="\033[m"

# =============================================================================
# DEPENDENCY CHECK
# =============================================================================

check_dependencies() {
  local missing=()

  if ! command -v jq &>/dev/null; then
    missing+=("jq")
  fi

  if ! command -v whiptail &>/dev/null; then
    missing+=("whiptail")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "${RD}Missing required dependencies: ${missing[*]}${CL}"
    echo -e "Install with: ${GN}apt install ${missing[*]}${CL}"
    exit 1
  fi

  if [[ ! -f "$METADATA_FILE" ]]; then
    echo -e "${RD}Metadata file not found: ${METADATA_FILE}${CL}"
    exit 1
  fi
}

# =============================================================================
# DATA LOADING (with caching for performance)
# =============================================================================

# Truncate string to max length
truncate() {
  local str="$1"
  local max="${2:-70}"
  if [[ ${#str} -gt $max ]]; then
    echo "${str:0:$((max-3))}..."
  else
    echo "$str"
  fi
}

# Script cache: jsonbase|slug|name|type|ram|os|categories|date|description
# jsonbase is the JSON filename without extension (for lookup when slug differs)
SCRIPT_CACHE=""

# Load all scripts into cache at startup (single pass)
load_script_cache() {
  echo -ne "${YW}Loading scripts...${CL}" >&2

  SCRIPT_CACHE=$(
    for json in "$JSON_DIR"/*.json; do
      local base
      base="$(basename "$json" .json)"
      [[ "$base" == "metadata" ]] && continue
      [[ "$base" == "versions" ]] && continue

      jq -r --arg base "$base" '
        [
          $base,
          .slug // "",
          .name // "Unknown",
          .type // "ct",
          (.install_methods[0].resources.ram // 512 | tostring),
          .install_methods[0].resources.os // "debian",
          (.categories // [] | map(tostring) | join(",")),
          .date_created // "1970-01-01",
          (.description // "" | gsub("\n"; " ") | .[0:100])
        ] | join("|")
      ' "$json" 2>/dev/null
    done
  )

  echo -e "\r\033[K" >&2
}

# Get JSON file path for a slug (handles slug != filename cases)
get_json_file() {
  local slug="$1"
  local jsonbase

  # Search cache for matching slug and get the jsonbase
  while IFS='|' read -r jbase s rest; do
    if [[ "$s" == "$slug" ]]; then
      jsonbase="$jbase"
      break
    fi
  done <<< "$SCRIPT_CACHE"

  if [[ -n "$jsonbase" ]]; then
    echo "${JSON_DIR}/${jsonbase}.json"
  else
    # Fallback to slug-based name
    echo "${JSON_DIR}/${slug}.json"
  fi
}

# Build category menu items array
get_categories() {
  jq -r '.categories | sort_by(.sort_order) | .[] | "\(.id)\n\(.name)"' "$METADATA_FILE"
}

# Format type for display with fixed width, padding on left
format_type() {
  local t
  case "$1" in
    ct)      t="LXC" ;;
    vm)      t="VM" ;;
    pve)     t="PVE" ;;
    addon)   t="ADDON" ;;
    turnkey) t="TURNKEY" ;;
    *)       t="${1^^}" ;;
  esac
  printf "%9s" "[$t]"
}

# Get scripts for a category ID (from cache)
get_scripts_by_category() {
  local cat_id="$1"

  while IFS='|' read -r jsonbase slug name type ram os categories date desc; do
    [[ -z "$slug" ]] && continue
    if [[ ",$categories," == *",$cat_id,"* ]]; then
      local display
      display=$(truncate "$(format_type "$type") $name")
      echo -e "${slug}\t${display}"
    fi
  done <<< "$SCRIPT_CACHE" | sort -t$'\t' -k1 | tr '\t' '\n'
}

# Get all scripts sorted by slug (from cache)
get_all_scripts() {
  while IFS='|' read -r jsonbase slug name type ram os categories date desc; do
    [[ -z "$slug" ]] && continue
    local display
    display=$(truncate "$(format_type "$type") $name")
    echo -e "${slug}\t${display}"
  done <<< "$SCRIPT_CACHE" | sort -t$'\t' -k1 | tr '\t' '\n'
}

# Get recently added scripts (from cache)
get_recent_scripts() {
  local count="${1:-25}"

  while IFS='|' read -r jsonbase slug name type ram os categories date desc; do
    [[ -z "$slug" ]] && continue
    local display
    display=$(truncate "$(format_type "$type") $name")
    echo -e "${date}\t${slug}\t${display}"
  done <<< "$SCRIPT_CACHE" | sort -t$'\t' -k1 -r | head -n "$count" | cut -f2,3 | tr '\t' '\n'
}

# Search scripts by name and description (from cache)
search_scripts() {
  local term="$1"
  local term_lower="${term,,}"

  while IFS='|' read -r jsonbase slug name type ram os categories date desc; do
    [[ -z "$slug" ]] && continue
    local name_lower="${name,,}"
    local desc_lower="${desc,,}"

    if [[ "$name_lower" == *"$term_lower"* ]] || [[ "$desc_lower" == *"$term_lower"* ]]; then
      local display
      display=$(truncate "$(format_type "$type") $name")
      echo -e "${slug}\t${display}"
    fi
  done <<< "$SCRIPT_CACHE" | sort -t$'\t' -k1 | tr '\t' '\n'
}

# Get script details
get_script_details() {
  local slug="$1"
  local json_file
  json_file=$(get_json_file "$slug")

  if [[ ! -f "$json_file" ]]; then
    echo "Script not found: $slug"
    return 1
  fi

  jq -r '
    "Name: \(.name)\n" +
    "Type: \(if .type == "ct" then "LXC Container" elif .type == "vm" then "Virtual Machine" else "PVE Tool" end)\n" +
    "─────────────────────────────────\n" +
    (if .type == "ct" or .type == "vm" then
      "Resources:\n" +
      "  CPU:  \(.install_methods[0].resources.cpu // 1) core(s)\n" +
      "  RAM:  \(.install_methods[0].resources.ram // 512) MB\n" +
      "  Disk: \(.install_methods[0].resources.hdd // 2) GB\n" +
      "  OS:   \(.install_methods[0].resources.os // "debian") \(.install_methods[0].resources.version // "")\n" +
      "─────────────────────────────────\n"
    else "" end) +
    (if .interface_port then "Port: \(.interface_port)\n" else "" end) +
    (if .documentation then "Docs: \(.documentation)\n" else "" end) +
    (if .interface_port or .documentation then "─────────────────────────────────\n" else "" end) +
    "\(.description // "No description available.")"
  ' "$json_file"
}

# Get install methods for a script
get_install_methods() {
  local slug="$1"
  local json_file
  json_file=$(get_json_file "$slug")

  if [[ ! -f "$json_file" ]]; then
    return 1
  fi

  local line_num=0
  while IFS= read -r line; do
    if (( line_num % 2 == 0 )); then
      echo "$line"  # script path - don't truncate
    else
      truncate "$line"  # description - truncate
    fi
    ((++line_num))
  done < <(jq -r '.install_methods[] | "\(.script)\n\(.type) (\(.resources.os) \(.resources.version // ""), \(.resources.ram)MB)"' "$json_file")
}

# =============================================================================
# MENUS
# =============================================================================

main_menu() {
  while true; do
    local choice
    choice=$(whiptail --backtitle "ProxmoxVE Helper Scripts" \
      --title "Main Menu" \
      --menu "Select an option:" 20 100 8 \
      "1" "Browse by Category" \
      "2" "Search Scripts" \
      "3" "List All (A-Z)" \
      "4" "Recently Added" \
      "5" "Exit" \
      3>&1 1>&2 2>&3) || break

    case "$choice" in
      1) category_menu ;;
      2) search_menu ;;
      3) all_scripts_menu ;;
      4) recent_menu ;;
      5) break ;;
    esac
  done
}

category_menu() {
  local categories
  mapfile -t categories < <(get_categories)

  if [[ ${#categories[@]} -eq 0 ]]; then
    whiptail --backtitle "ProxmoxVE Helper Scripts" \
      --title "Error" \
      --msgbox "No categories found." 10 100
    return
  fi

  local choice
  choice=$(whiptail --backtitle "ProxmoxVE Helper Scripts" \
    --title "Categories" \
    --menu "Select a category:" 35 100 25 \
    "${categories[@]}" \
    3>&1 1>&2 2>&3) || return

  scripts_menu "$choice" "category"
}

scripts_menu() {
  local filter_value="$1"
  local filter_type="$2"
  local scripts

  case "$filter_type" in
    category)
      mapfile -t scripts < <(get_scripts_by_category "$filter_value")
      ;;
    search)
      mapfile -t scripts < <(search_scripts "$filter_value")
      ;;
    all)
      mapfile -t scripts < <(get_all_scripts)
      ;;
    recent)
      mapfile -t scripts < <(get_recent_scripts 25)
      ;;
  esac

  if [[ ${#scripts[@]} -eq 0 ]]; then
    whiptail --backtitle "ProxmoxVE Helper Scripts" \
      --title "No Results" \
      --msgbox "No scripts found." 10 100
    return
  fi

  local choice
  choice=$(whiptail --backtitle "ProxmoxVE Helper Scripts" \
    --title "Scripts" \
    --menu "Select a script:" 35 100 25 \
    "${scripts[@]}" \
    3>&1 1>&2 2>&3) || return

  script_details_menu "$choice"
}

search_menu() {
  local term
  term=$(whiptail --backtitle "ProxmoxVE Helper Scripts" \
    --title "Search" \
    --inputbox "Enter search term (name or description):" 12 100 \
    3>&1 1>&2 2>&3) || return

  if [[ -z "$term" ]]; then
    return
  fi

  scripts_menu "$term" "search"
}

all_scripts_menu() {
  scripts_menu "" "all"
}

recent_menu() {
  scripts_menu "" "recent"
}

script_details_menu() {
  local slug="$1"
  local details
  details=$(get_script_details "$slug")

  if whiptail --backtitle "ProxmoxVE Helper Scripts" \
    --title "$slug" \
    --yes-button "Run" \
    --no-button "Back" \
    --yesno "$details" 35 100; then

    select_and_run "$slug"
  fi
}

select_and_run() {
  local slug="$1"

  # Get install methods
  local methods
  mapfile -t methods < <(get_install_methods "$slug")

  local method_count=$((${#methods[@]} / 2))
  local script_path

  if [[ $method_count -eq 0 ]]; then
    whiptail --backtitle "ProxmoxVE Helper Scripts" \
      --title "Error" \
      --msgbox "No install methods found for $slug" 10 100
    return
  elif [[ $method_count -eq 1 ]]; then
    script_path="${methods[0]}"
  else
    # Multiple methods - let user choose
    script_path=$(whiptail --backtitle "ProxmoxVE Helper Scripts" \
      --title "Select Method" \
      --menu "Select method:" 22 100 12 \
      "${methods[@]}" \
      3>&1 1>&2 2>&3) || return
  fi

  # Confirm and run
  if whiptail --backtitle "ProxmoxVE Helper Scripts" \
    --title "Confirm" \
    --yesno "Run script?\n\n${script_path}" 12 100; then

    clear
    echo -e "${GN}Launching: ${script_path}${CL}"
    echo ""

    local full_path="${SCRIPT_DIR}/${script_path}"
    if [[ -f "$full_path" ]]; then
      bash "$full_path"
    else
      echo -e "${RD}Script not found: ${full_path}${CL}"
      exit 1
    fi
  fi
}

# =============================================================================
# MAIN
# =============================================================================

check_dependencies
load_script_cache
main_menu

echo -e "${GN}Goodbye!${CL}"
