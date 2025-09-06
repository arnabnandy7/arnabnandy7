#!/usr/bin/env bash
set -euo pipefail

# ----------------- CONFIG -----------------
PETROL_FILE="tmp/petrol_price.json"
DIESEL_FILE="tmp/diesel_price.json"
CITY="${CITY:-Kolkata}"           # city to display (can be overridden via env)
PLACEHOLDER="[fuel_cards]"     # exact placeholder in README.md to replace
README="README.md"
# ------------------------------------------

# helper: safe jq extraction returns empty string if not found or file missing
get_field() {
  local file="$1"
  local city="$2"
  local field="$3"
  if [[ ! -f "$file" ]]; then
    echo ""
    return
  fi
  jq -r --arg c "$city" --arg f "$field" '(.[] | select(.city == $c) | .[$f]) // ""' "$file" 2>/dev/null || echo ""
}

# decorate change -> "🔺 0.12" and dir (up/down/neutral)
decorate_change() {
  local ch="$1"
  if [[ -z "$ch" ]]; then
    printf "%s\\n" "— neutral"
  elif [[ "$ch" == +* ]]; then
    # strip leading + in display
    printf "%s\\n" "🔺 ${ch#+} up"
  elif [[ "$ch" == -* ]]; then
    printf "%s\\n" "🔻 ${ch#-} down"
  else
    printf "%s\\n" "${ch} neutral"
  fi
}

# Read values (empty string if not present)
PETROL_PRICE=$(get_field "$PETROL_FILE" "$CITY" "price")
PETROL_CHANGE_RAW=$(get_field "$PETROL_FILE" "$CITY" "change")
read -r PETROL_CHANGE_DECOR PETROL_DIR <<< "$(decorate_change "$PETROL_CHANGE_RAW")"

DIESEL_PRICE=$(get_field "$DIESEL_FILE" "$CITY" "price")
DIESEL_CHANGE_RAW=$(get_field "$DIESEL_FILE" "$CITY" "change")
read -r DIESEL_CHANGE_DECOR DIESEL_DIR <<< "$(decorate_change "$DIESEL_CHANGE_RAW")"

# Fallbacks for missing values
[[ -z "$PETROL_PRICE" ]] && PETROL_PRICE="—"
[[ -z "$DIESEL_PRICE" ]] && DIESEL_PRICE="—"
[[ -z "$PETROL_CHANGE_DECOR" ]] && PETROL_CHANGE_DECOR="—"
[[ -z "$DIESEL_CHANGE_DECOR" ]] && DIESEL_CHANGE_DECOR="—"
[[ -z "$PETROL_DIR" ]] && PETROL_DIR="neutral"
[[ -z "$DIESEL_DIR" ]] && DIESEL_DIR="neutral"

# Date in DD/MM/YYYY
UPDATED_DATE=$(date +"%d/%m/%Y")

# Determine color hex for change display
color_for() {
  local dir="$1"
  if [[ "$dir" == "up" ]]; then
    echo "#2f7a2f"   # green
  elif [[ "$dir" == "down" ]]; then
    echo "#b02f2f"   # red
  else
    echo "#6b6b6b"   # gray
  fi
}

PETROL_COLOR=$(color_for "$PETROL_DIR")
DIESEL_COLOR=$(color_for "$DIESEL_DIR")

# Build HTML snippet (preserve whitespace/newlines)
CARDS_HTML=$(cat <<EOF
<div style="display:flex;gap:14px;flex-wrap:wrap;align-items:stretch">
  <div style="flex:1;min-width:220px;border-radius:10px;padding:12px;background:#fff8ef;border:1px solid #f1d6b0;">
    <div style="display:flex;align-items:center;gap:10px">
      <div style="font-size:20px">⛽</div>
      <div>
        <div style="font-weight:700;font-size:14px;color:#8a4b00">Petrol — ${CITY}</div>
        <div style="font-size:12px;color:#7a6a56">Updated: ${UPDATED_DATE}</div>
      </div>
    </div>
    <div style="margin-top:10px;font-size:20px;font-weight:800">₹${PETROL_PRICE}</div>
    <div style="margin-top:6px;font-size:14px;color:${PETROL_COLOR}">${PETROL_CHANGE_DECOR}</div>
  </div>

  <div style="flex:1;min-width:220px;border-radius:10px;padding:12px;background:#eef7ff;border:1px solid #cfe6fb;">
    <div style="display:flex;align-items:center;gap:10px">
      <div style="font-size:20px">🛢️</div>
      <div>
        <div style="font-weight:700;font-size:14px;color:#08406a">Diesel — ${CITY}</div>
        <div style="font-size:12px;color:#577085">Updated: ${UPDATED_DATE}</div>
      </div>
    </div>
    <div style="margin-top:10px;font-size:20px;font-weight:800">₹${DIESEL_PRICE}</div>
    <div style="margin-top:6px;font-size:14px;color:${DIESEL_COLOR}">${DIESEL_CHANGE_DECOR}</div>
  </div>
</div>
EOF
)

# Replace placeholder in README.md safely using Python (handles arbitrary text)
if [[ -f "$README" ]]; then
  TMP_CARDS_FILE=$(mktemp)
  printf '%s' "$CARDS_HTML" > "$TMP_CARDS_FILE"

  python3 - <<PY
import io,sys
readme = "$README"
cards_file = "$TMP_CARDS_FILE"
placeholder = "$PLACEHOLDER"

try:
    with io.open(readme, 'r', encoding='utf-8') as f:
        text = f.read()
except Exception as e:
    sys.stderr.write("Error reading README: " + str(e) + "\\n")
    sys.exit(1)

try:
    with io.open(cards_file, 'r', encoding='utf-8') as f:
        cards = f.read()
except Exception as e:
    sys.stderr.write("Error reading cards temp file: " + str(e) + "\\n")
    sys.exit(1)

if placeholder not in text:
    sys.stderr.write("⚠️ Placeholder '{}' not found in {}\\n".format(placeholder, readme))
    # still write file with no change to keep action non-fatal
    sys.exit(0)

new_text = text.replace(placeholder, cards)
try:
    with io.open(readme, 'w', encoding='utf-8') as f:
        f.write(new_text)
except Exception as e:
    sys.stderr.write("Error writing README: " + str(e) + "\\n")
    sys.exit(1)
PY

  rm -f "$TMP_CARDS_FILE"
  echo "✅ README.md updated with fuel cards for ${CITY}."
else
  echo "⚠️ ${README} not found — printing cards to stdout:"
  echo
  printf '%s\n' "$CARDS_HTML"
fi
