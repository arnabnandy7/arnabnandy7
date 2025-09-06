#!/usr/bin/env bash
set -euo pipefail

# ---------- CONFIG ----------
PETROL_FILE="tmp/petrol_price.json"
DIESEL_FILE="tmp/diesel_price.json"
CITY="Kolkata"             # city to display
PLACEHOLDER="\[fuel_cards\]"
README="README.md"
# ----------------------------

# helper to read field using jq
get_field() {
  local file="$1" city="$2" field="$3"
  jq -r --arg c "$city" --arg f "$field" '(.[] | select(.city == $c) | .[$f]) // ""' "$file" 2>/dev/null || echo ""
}

decorate_change() {
  local ch="$1"
  if [[ -z "$ch" ]]; then
    echo "—" "neutral"
  elif [[ "$ch" == +* ]]; then
    echo "🔺 ${ch#+}" "up"
  elif [[ "$ch" == -* ]]; then
    echo "🔻 ${ch#-}" "down"
  else
    echo "$ch" "neutral"
  fi
}

# read values
PETROL_PRICE=$(get_field "$PETROL_FILE" "$CITY" "price")
PETROL_CHANGE_RAW=$(get_field "$PETROL_FILE" "$CITY" "change")
read -r PETROL_CHANGE_DECOR PETROL_DIR <<< "$(decorate_change "$PETROL_CHANGE_RAW")"

DIESEL_PRICE=$(get_field "$DIESEL_FILE" "$CITY" "price")
DIESEL_CHANGE_RAW=$(get_field "$DIESEL_FILE" "$CITY" "change")
read -r DIESEL_CHANGE_DECOR DIESEL_DIR <<< "$(decorate_change "$DIESEL_CHANGE_RAW")"

# fallbacks
[[ -z "$PETROL_PRICE" ]] && PETROL_PRICE="—"
[[ -z "$DIESEL_PRICE" ]] && DIESEL_PRICE="—"
[[ -z "$PETROL_CHANGE_DECOR" ]] && PETROL_CHANGE_DECOR="—"
[[ -z "$DIESEL_CHANGE_DECOR" ]] && DIESEL_CHANGE_DECOR="—"

# date in DD/MM/YYYY
UPDATED_DATE=$(date +"%d/%m/%Y")

# build HTML snippet (inline HTML works in GitHub README)
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
    <div style="margin-top:6px;font-size:14px;color:$( [[ "$PETROL_DIR" == "up" ]] && echo '#2f7a2f' || ([[ "$PETROL_DIR" == "down" ]] && echo '#b02f2f' || echo '#6b6b6b') )">${PETROL_CHANGE_DECOR}</div>
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
    <div style="margin-top:6px;font-size:14px;color:$( [[ "$DIESEL_DIR" == "up" ]] && echo '#2f7a2f' || ([[ "$DIESEL_DIR" == "down" ]] && echo '#b02f2f' || echo '#6b6b6b') )">${DIESEL_CHANGE_DECOR}</div>
  </div>
</div>
EOF
)

# Replace placeholder in README.md
if [[ -f "$README" ]]; then
  # escape for sed (preserve newlines)
  esc() { printf '%s' "$1" | sed -e 's/[\/&]/\\&/g' -e ':a;N;$!ba;s/\n/\\n/g'; }
  TMP=$(mktemp)
  cp "$README" "$TMP"
  sed -i "s/${PLACEHOLDER}/$(esc "$CARDS_HTML")/g" "$TMP"
  mv "$TMP" "$README"
  echo "✅ README.md updated with fuel cards for ${CITY}."
else
  echo "⚠️ ${README} not found — printing cards to stdout:"
  echo
  echo "$CARDS_HTML"
fi
