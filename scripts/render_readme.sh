#!/usr/bin/env bash
set -euo pipefail

README_PATH="${README_PATH:-README.md}"

usage() {
  echo "Usage: $0 replace PLACEHOLDER VALUE | validate" >&2
  exit 2
}

case "${1:-}" in
  replace)
    [[ $# -eq 3 ]] || usage
    [[ -f "$README_PATH" ]] || { echo "Missing $README_PATH" >&2; exit 1; }
    PLACEHOLDER="$2" REPLACEMENT="$3" perl -0pi -e '
      $count = s/\Q$ENV{PLACEHOLDER}\E/$ENV{REPLACEMENT}/g;
      END { exit 3 unless $count }
    ' "$README_PATH" || {
      status=$?
      [[ $status -eq 3 ]] && echo "Missing placeholder $2 in $README_PATH" >&2
      exit "$status"
    }
    ;;
  validate)
    [[ $# -eq 1 ]] || usage
    placeholders=(
      '[contribution_summary]' '[date]' '[icon]' '[todays_condition]'
      '[todays_condition_in_bengali]' '[weather_dashboard]' '[aqi]'
      '[PM2_5]' '[PM10]' '[hourly_forecast_table]' '[crypto_prices]'
      '[funny_no_statement]' '[current_year_placeholder]' '[fuel_price]'
    )
    missing=0
    for placeholder in "${placeholders[@]}"; do
      if grep -Fq "$placeholder" "$README_PATH"; then
        echo "Unresolved placeholder $placeholder in $README_PATH" >&2
        missing=1
      fi
    done
    exit "$missing"
    ;;
  *) usage ;;
esac
