#!/usr/bin/env bash
set -euo pipefail

PETROL_FILE="tmp/petrol_price.json"
DIESEL_FILE="tmp/diesel_price.json"
CITY="${CITY:-Kolkata}"   # default Agar if not passed
PLACEHOLDER="[fuel_price]"
README="README.md"

# helper to extract value from JSON
get_field() {
  local file="$1" city="$2" field="$3"
  if [[ -f "$file" ]]; then
    jq -r --arg c "$city" --arg f "$field" \
      '(.[] | select(.city == $c) | .[$f]) // empty' "$file" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

# get prices and changes
PETROL_PRICE=$(get_field "$PETROL_FILE" "$CITY" "price")
PETROL_CHANGE=$(get_field "$PETROL_FILE" "$CITY" "change")
DIESEL_PRICE=$(get_field "$DIESEL_FILE" "$CITY" "price")
DIESEL_CHANGE=$(get_field "$DIESEL_FILE" "$CITY" "change")

# decorate with arrows
decorate() {
  local val="$1"
  if [[ "$val" == +* ]]; then
    echo "🔺"
  elif [[ "$val" == -* ]]; then
    echo "🔻"
  else
    echo "➖"
  fi
}

PETROL_ARROW=$(decorate "$PETROL_CHANGE")
DIESEL_ARROW=$(decorate "$DIESEL_CHANGE")

[[ -z "$PETROL_PRICE" ]] && PETROL_PRICE="—"
[[ -z "$DIESEL_PRICE" ]] && DIESEL_PRICE="—"

# final one-liner
FUEL_LINE="⛽ Petrol: ₹${PETROL_PRICE} ${PETROL_ARROW} 🛢️ Diesel: ₹${DIESEL_PRICE} ${DIESEL_ARROW}"

# replace in README
if [[ -f "$README" ]]; then
  sed -i "s#\[fuel_price\]#${FUEL_LINE//$'\n'/\\n}#g" README.md
  echo "✅ Updated README with fuel prices for ${CITY}"
else
  echo "⚠️ README.md not found, showing line:"
  echo "$FUEL_LINE"
fi
