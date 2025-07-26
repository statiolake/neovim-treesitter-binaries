#!/bin/bash
set -euo pipefail

cleanup_and_exit() {
  local output_file="$1"
  local nvim_pid="$2"
  local exit_code="$3"
  local message="$4"

  kill "$nvim_pid" 2>/dev/null || true
  echo "$message"
  rm -f "$output_file"
  return "$exit_code"
}

check_memory_error() {
  local content="$1"
  echo "$content" | grep -q "Out of memory"
}

check_up_to_date() {
  local content="$1"
  echo "$content" | grep -q "up-to-date"
}

check_installation_complete() {
  local content="$1"

  echo "$content" | grep -q "installed" || return 1

  local progress=$(echo "$content" | grep -o '\[[0-9]\+/[0-9]\+\]' | tail -1)
  [ -n "$progress" ] || return 1

  local current=$(echo "$progress" | sed 's/\[\([0-9]\+\)\/\([0-9]\+\)\]/\1/')
  local total=$(echo "$progress" | sed 's/\[\([0-9]\+\)\/\([0-9]\+\)\]/\2/')

  [ "$current" = "$total" ] && [ "$current" != "0" ]
}

monitor_output_content() {
  local output_file="$1"
  local nvim_pid="$2"

  [ -f "$output_file" ] || return 1

  local content=$(tail -c 1000 "$output_file" 2>/dev/null || echo "")

  if check_memory_error "$content"; then
    cleanup_and_exit "$output_file" "$nvim_pid" 1 "ERROR: out of memory"
    return $?
  fi

  if check_up_to_date "$content"; then
    cleanup_and_exit "$output_file" "$nvim_pid" 0 "DONE: all parser are up-to-date"
    return $?
  fi

  if check_installation_complete "$content"; then
    cleanup_and_exit "$output_file" "$nvim_pid" 0 "DONE: all parsers installed"
    return $?
  fi

  return 1
}

run_treesitter_command() {
  local cmd="$1"
  local timeout_seconds=720  # 12 minutes
  local output_file=$(mktemp)

  echo "Running: nvim --headless -c '$cmd'"

  # Run command in background and capture stderr
  timeout $timeout_seconds nvim --headless -c "$cmd" 2> "$output_file" &
  local nvim_pid=$!

  # Monitor output
  while kill -0 $nvim_pid 2>/dev/null; do
    if monitor_output_content "$output_file" "$nvim_pid"; then
      return $?
    fi
    sleep 1
  done

  # Check if process completed normally
  wait $nvim_pid
  local exit_code=$?

  if [ $exit_code -eq 124 ]; then
    echo "ERROR: time out"
    rm -f "$output_file"
    return 1
  fi

  rm -f "$output_file"
  return $exit_code
}

# Install all parsers
run_treesitter_command "TSInstall all"