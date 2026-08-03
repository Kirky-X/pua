#!/bin/bash
# PUA shared helper: portable timeout wrapper
# Source this file in hooks/tests that need timeout functionality.
# macOS does not ship GNU `timeout`; Homebrew may provide `gtimeout`,
# and Perl is available by default on macOS/Linux.

run_with_timeout() {
  local seconds="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$seconds" "$@"
  else
    perl -e '
      my $seconds = shift @ARGV;
      $SIG{ALRM} = sub { exit 124 };
      alarm($seconds);
      exec @ARGV;
    ' "$seconds" "$@"
  fi
}
