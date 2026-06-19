#!/bin/bash
set -euo pipefail

USERNAME="yunus25jmi1"
README="README.md"
DAYS_BACK=7

gh_api() {
    local endpoint="$1"
    if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
        gh api "$endpoint" 2>/dev/null
    elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
        curl -sf -H "Authorization: Bearer $GITHUB_TOKEN" \
             -H "Accept: application/vnd.github.v3+json" \
             "https://api.github.com${endpoint}"
    else
        curl -sf -H "Accept: application/vnd.github.v3+json" \
             "https://api.github.com${endpoint}"
    fi
}

profile=$(gh_api "/users/$USERNAME")
REPOS=$(echo "$profile" | jq -r '.public_repos // 0')
FOLLOWERS=$(echo "$profile" | jq -r '.followers // 0')

YEAR=$(date '+%Y')
FROM="${YEAR}-01-01T00:00:00Z"
TO=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

resp=$(gh api graphql -f query='query($login:String!,$from:DateTime!,$to:DateTime!){user(login:$login){contributionsCollection(from:$from,to:$to){totalCommitContributions totalPullRequestContributions}repositories(first:100,ownerAffiliations:OWNER){nodes{stargazerCount}}}}' -f login="$USERNAME" -f from="$FROM" -f to="$TO" 2>/dev/null || echo "{}")

COMMITS=$(echo "$resp" | jq -r '.data.user.contributionsCollection.totalCommitContributions // 0')
PRS=$(echo "$resp" | jq -r '.data.user.contributionsCollection.totalPullRequestContributions // 0')
STARS=$(echo "$resp" | jq -r '[.data.user.repositories.nodes[]?.stargazerCount // 0] | add // 0')

SINCE=$(date -d "$DAYS_BACK days ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -v-${DAYS_BACK}d '+%Y-%m-%dT%H:%M:%SZ')
EVENTS=$(gh_api "/users/$USERNAME/events?per_page=100")

TABLE_ROWS=""
while IFS= read -r event; do
    [[ "$event" == "null" || -z "$event" ]] && continue
    DATE=$(echo "$event" | jq -r '.created_at | split("T")[0]')
    TYPE=$(echo "$event" | jq -r '.type')
    REPO=$(echo "$event" | jq -r '.repo.name')
    REPO_URL="https://github.com/$REPO"
    REPO_OWNER=$(echo "$REPO" | cut -d'/' -f1)
    REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)
    ENCODED=$(echo "$REPO_NAME" | sed 's/-/--/g')

    case "$TYPE" in
        PushEvent)          ACTION="Push"; DETAIL="commit(s)"; ICON="✅" ;;
        PullRequestEvent)   ACTION="PR #$(echo "$event" | jq -r '.payload.number // "?"'): $(echo "$event" | jq -r '.payload.action // ""')"; DETAIL=$(echo "$event" | jq -r '.payload.pull_request.title // "PR"' | head -c 60); ICON="🔀" ;;
        CreateEvent)        ACTION="Created: $(echo "$event" | jq -r '.payload.ref_type // ""')"; DETAIL=$(echo "$event" | jq -r '.payload.ref // "repo"'); ICON="🚀" ;;
        IssuesEvent)        ACTION="Issue #$(echo "$event" | jq -r '.payload.issue.number // "?"'): $(echo "$event" | jq -r '.payload.action // ""')"; DETAIL=$(echo "$event" | jq -r '.payload.issue.title // "Issue"' | head -c 60); ICON="🐛" ;;
        *)                  ACTION="$TYPE"; DETAIL=""; ICON="📝" ;;
    esac

    TABLE_ROWS+="  <tr>
    <td><strong>${DATE}</strong></td>
    <td><a href=\"${REPO_URL}\"><img src=\"https://img.shields.io/badge/${REPO_OWNER}-${ENCODED}-0366d6?style=flat&logo=github\" alt=\"${REPO}\"></a></td>
    <td><strong>${ACTION}</strong><br><small>${DETAIL}</small></td>
    <td>${ICON}</td>
  </tr>
"
done < <(echo "$EVENTS" | jq -c --arg s "$SINCE" '[.[] | select(.created_at >= $s) | select(.type=="PushEvent" or .type=="PullRequestEvent" or .type=="CreateEvent" or .type=="IssuesEvent")] | sort_by(.created_at) | reverse | .[0:10] | .[]' 2>/dev/null)

[[ -z "$TABLE_ROWS" ]] && TABLE_ROWS="  <tr><td colspan=\"4\" align=\"center\"><em>No recent public activity</em></td></tr>"
printf '%s' "$TABLE_ROWS" > /tmp/readme_table_rows.txt

python3 - "$README" "$REPOS" "$COMMITS" "$PRS" "$STARS" "$FOLLOWERS" "$YEAR" <<'PYEOF'
import re, sys

readme = open(sys.argv[1], encoding='utf-8').read()
html_rows = open('/tmp/readme_table_rows.txt', encoding='utf-8').read()
repos, commits, prs, stars, followers, year = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6], sys.argv[7]

auto_block = (
    '#### Recent Contributions (Last 7 Days)\n'
    '<table width="100%">\n'
    '  <tr>\n'
    '    <th width="15%">Date</th>\n'
    '    <th width="40%">Repository</th>\n'
    '    <th width="30%">Contribution</th>\n'
    '    <th width="15%">Status</th>\n'
    '  </tr>\n'
    f'{html_rows}</table>\n\n'
    '#### Contribution Impact\n'
    '<div align="center">\n'
    '  <table>\n'
    '    <tr>\n'
    f'      <td align="center"><img src="https://img.shields.io/badge/Commits_({year})-{commits}-FF4500?style=for-the-badge"></td>\n'
    f'      <td align="center"><img src="https://img.shields.io/badge/Pull_Requests-{prs}-8A2BE2?style=for-the-badge"></td>\n'
    f'      <td align="center"><img src="https://img.shields.io/badge/Repos-{repos}-32CD32?style=for-the-badge"></td>\n'
    f'      <td align="center"><img src="https://img.shields.io/badge/Stars-{stars}-FFD700?style=for-the-badge"></td>\n'
    f'      <td align="center"><img src="https://img.shields.io/badge/Followers-{followers}-00D4AA?style=for-the-badge"></td>\n'
    '    </tr>\n'
    '  </table>\n'
    '</div>'
)

readme = re.sub(
    r'<!-- AUTO-START -->.*?<!-- AUTO-END -->',
    f'<!-- AUTO-START -->\n{auto_block}\n<!-- AUTO-END -->',
    readme, count=1, flags=re.DOTALL
)

open(sys.argv[1], 'w', encoding='utf-8').write(readme)
print(f"Done: repos={repos} commits={commits} prs={prs} stars={stars}")
PYEOF

rm -f /tmp/readme_table_rows.txt
