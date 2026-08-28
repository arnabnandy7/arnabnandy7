#!/usr/bin/env bash
set -euo pipefail

USERNAME="${CONTRIBUTIONS_USERNAME:-arnabnandy7}"
README_PATH="README.md"
DOC_PATH="docs/contributions.md"
PLACEHOLDER="[contribution_summary]"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

all_items="$work_dir/all-items.json"
sorted_items="$work_dir/sorted-items.json"
summary="$work_dir/summary.md"
rendered_readme="$work_dir/README.md"
printf '[]\n' > "$all_items"

base_query="is:pr is:merged author:${USERNAME} -user:${USERNAME}"
request_count=0

api_search() {
  local raw_query="$1" page="$2" output="$3" encoded_query
  encoded_query=$(jq -rn --arg query "$raw_query" '$query | @uri')
  headers=(
    -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2022-11-28"
    -H "User-Agent: ${USERNAME}-profile-readme"
  )
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  curl --fail-with-body --silent --show-error \
    "${headers[@]}" \
    "https://api.github.com/search/issues?q=${encoded_query}&sort=updated&order=desc&per_page=100&page=${page}" \
    --output "$output"
}

append_items() {
  local response="$1"
  jq -s '.[0] + .[1].items' "$all_items" "$response" > "$work_dir/combined.json"
  mv "$work_dir/combined.json" "$all_items"
}

fetch_pages() {
  local raw_query="$1" first_response="$2" total_count="$3"
  local page=1 response="$first_response" fetched=0 batch_size
  while :; do
    append_items "$response"
    batch_size=$(jq '.items | length' "$response")
    ((fetched += batch_size))
    (( batch_size < 100 || fetched >= total_count )) && break
    ((page += 1))
    response="$work_dir/response-$((++request_count)).json"
    api_search "$raw_query" "$page" "$response"
  done
}

fetch_window() {
  local start_date="$1" end_date="$2" window_query response total_count
  local start_epoch end_epoch midpoint_epoch midpoint_date next_date
  window_query="${base_query} created:${start_date}..${end_date}"
  response="$work_dir/response-$((++request_count)).json"
  api_search "$window_query" 1 "$response"
  total_count=$(jq '.total_count' "$response")

  if (( total_count <= 1000 )); then
    fetch_pages "$window_query" "$response" "$total_count"
    return
  fi
  if [[ "$start_date" == "$end_date" ]]; then
    echo "More than 1,000 contributions found on $start_date; GitHub Search cannot return complete results." >&2
    exit 1
  fi

  start_epoch=$(date -u -d "$start_date" +%s)
  end_epoch=$(date -u -d "$end_date" +%s)
  midpoint_epoch=$(( (start_epoch + end_epoch) / 2 ))
  midpoint_date=$(date -u -d "@${midpoint_epoch}" +%F)
  next_date=$(date -u -d "${midpoint_date} + 1 day" +%F)
  fetch_window "$start_date" "$midpoint_date"
  fetch_window "$next_date" "$end_date"
}

initial_response="$work_dir/response-$((++request_count)).json"
api_search "$base_query" 1 "$initial_response"
total_count=$(jq '.total_count' "$initial_response")
if (( total_count <= 1000 )); then
  fetch_pages "$base_query" "$initial_response" "$total_count"
else
  fetch_window "2008-01-01" "$(date -u +%F)"
fi

# The query excludes owned repositories; this owner check is an additional guard.
jq --arg username "${USERNAME,,}" '
  def repository_name: .repository_url | sub("^https://api.github.com/repos/"; "");
  unique_by(.id)
  | map(select((repository_name | split("/")[0] | ascii_downcase) != $username))
  | sort_by(.closed_at) | reverse
' "$all_items" > "$sorted_items"

markdown_rows() {
  local limit="${1:-}"
  local filter='.[]'
  [[ -n "$limit" ]] && filter=".[:${limit}][]"

  jq -r "$filter"' |
    def repository_name: .repository_url | tostring | sub("^https://api.github.com/repos/"; "");
    def repository_owner: repository_name | split("/")[0];
    def markdown_text: tostring | gsub("\\|"; "\\\\|") | gsub("[\\r\\n]"; " ");
    "| <img src=\"https://github.com/\(repository_owner).png?size=24\" width=\"24\" height=\"24\" alt=\"\(repository_owner) avatar\"> [\(repository_name)](https://github.com/\(repository_name)) | [#\(.number) - \(.title | markdown_text)](\(.html_url)) | \(.closed_at[0:10]) |"
  ' "$sorted_items"
}

repository_summary_rows() {
  jq -r --arg username "$USERNAME" '
    def repository_name: .repository_url | tostring | sub("^https://api.github.com/repos/"; "");
    def repository_owner: repository_name | split("/")[0];
    map({ name: repository_name, owner: repository_owner })
    | sort_by(.name)
    | group_by(.name)
    | map({
        name: .[0].name,
        owner: .[0].owner,
        label: (.[0].name | split("/")[1]),
        count: length
      })
    | sort_by([-.count, (.name | ascii_downcase)])
    | .[:15]
    | map(
        "<img src=\"https://github.com/\(.owner).png?size=20\" width=\"20\" height=\"20\" valign=\"middle\" alt=\"\(.owner) avatar\"> <a href=\"https://github.com/\(.name)\">\(.label)</a> (<a href=\"https://github.com/\(.name)/pulls?q=is%3Apr+is%3Amerged+author%3A\($username)\"><strong>\(.count)</strong></a>)"
      )
    | . as $repositories
    | range(0; length; 5) as $index
    | "  <tr><td align=\"left\" valign=\"middle\" width=\"20%\">\($repositories[$index])</td><td align=\"left\" valign=\"middle\" width=\"20%\">\($repositories[$index + 1] // "")</td><td align=\"left\" valign=\"middle\" width=\"20%\">\($repositories[$index + 2] // "")</td><td align=\"left\" valign=\"middle\" width=\"20%\">\($repositories[$index + 3] // "")</td><td align=\"left\" valign=\"middle\" width=\"20%\">\($repositories[$index + 4] // "")</td></tr>"
  ' "$sorted_items"
}

organization_summary_rows() {
  jq -r --arg username "$USERNAME" '
    def repository_name: .repository_url | tostring | sub("^https://api.github.com/repos/"; "");
    def repository_owner: repository_name | split("/")[0];
    map(repository_owner)
    | sort_by(ascii_downcase)
    | group_by(ascii_downcase)
    | map({ name: .[0], count: length })
    | sort_by([-.count, (.name | ascii_downcase)])
    | .[:10]
    | map(
        "<img src=\"https://github.com/\(.name).png?size=20\" width=\"20\" height=\"20\" valign=\"middle\" alt=\"\(.name) avatar\"> <a href=\"https://github.com/\(.name)\">\(.name)</a> (<a href=\"https://github.com/pulls?q=is%3Apr+is%3Amerged+author%3A\($username)+org%3A\(.name)\"><strong>\(.count)</strong></a>)"
      )
    | . as $organizations
    | range(0; length; 5) as $index
    | "  <tr><td align=\"left\" valign=\"middle\" width=\"20%\">\($organizations[$index])</td><td align=\"left\" valign=\"middle\" width=\"20%\">\($organizations[$index + 1] // "")</td><td align=\"left\" valign=\"middle\" width=\"20%\">\($organizations[$index + 2] // "")</td><td align=\"left\" valign=\"middle\" width=\"20%\">\($organizations[$index + 3] // "")</td><td align=\"left\" valign=\"middle\" width=\"20%\">\($organizations[$index + 4] // "")</td></tr>"
  ' "$sorted_items"
}

if [[ $(jq 'length' "$sorted_items") -eq 0 ]]; then
  printf 'No merged pull requests found yet.\n' > "$summary"
  else
  {
    printf '<h4 align="center">Top organizations / users</h4>\n\n'
    printf '<table width="100%%" cellpadding="10" cellspacing="0">\n'
    organization_summary_rows
    printf '</table>\n\n'
    printf '<h4 align="center">Top repositories</h4>\n\n'
    printf '<table width="100%%" cellpadding="10" cellspacing="0">\n'
    repository_summary_rows
    printf '</table>\n'
    printf '\n[Explore the complete open source quest log](./docs/contributions.md)\n'
  } > "$summary"
fi

awk -v placeholder="$PLACEHOLDER" -v summary_file="$summary" '
  $0 == placeholder {
    while ((getline line < summary_file) > 0) print line
    close(summary_file)
    next
  }
  { print }
' "$README_PATH" > "$rendered_readme"

if cmp -s "$README_PATH" "$rendered_readme"; then
  if ! grep -Fxq "$PLACEHOLDER" "$README_PATH"; then
    echo "Missing $PLACEHOLDER in $README_PATH" >&2
    exit 1
  fi
fi
mv "$rendered_readme" "$README_PATH"

mkdir -p "$(dirname "$DOC_PATH")"
{
  printf '# Open Source Quest Log\n\n'
  printf 'Merged contributions by [@%s](https://github.com/%s) to external repositories, newest merges first.\n\n' "$USERNAME" "$USERNAME"
  printf 'This quest log is refreshed automatically by the profile README workflow.\n\n'
  if [[ $(jq 'length' "$sorted_items") -eq 0 ]]; then
    printf 'No merged pull requests found yet.\n'
  else
    printf '| Repository | Contribution | Merged |\n'
    printf '| :---: | :---: | :---: |\n'
    markdown_rows
  fi
} > "$DOC_PATH"

echo "Generated external contribution quest log"
