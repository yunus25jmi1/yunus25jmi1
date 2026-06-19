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

# Fetch profile stats
profile=$(gh_api "/users/$USERNAME")
REPOS=$(echo "$profile" | jq -r '.public_repos // 0')
GISTS=$(echo "$profile" | jq -r '.public_gists // 0')
FOLLOWERS=$(echo "$profile" | jq -r '.followers // 0')
FOLLOWING=$(echo "$profile" | jq -r '.following // 0')

# Fetch contribution stats via GraphQL
YEAR=$(date '+%Y')
FROM="${YEAR}-01-01T00:00:00Z"
TO=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

GQL='query($login:String!,$from:DateTime!,$to:DateTime!){
  user(login:$login){
    contributionsCollection(from:$from,to:$to){
      totalCommitContributions
      totalPullRequestContributions
      totalIssueContributions
      totalPullRequestReviewContributions
    }
    repositories(first:100,ownerAffiliations:OWNER){
      nodes{stargazerCount forkCount}
    }
  }
}'

resp=$(gh api graphql -f query="$GQL" -f login="$USERNAME" -f from="$FROM" -f to="$TO" 2>/dev/null || echo "{}")

COMMITS=$(echo "$resp" | jq -r '.data.user.contributionsCollection.totalCommitContributions // 0')
PRS=$(echo "$resp" | jq -r '.data.user.contributionsCollection.totalPullRequestContributions // 0')
ISSUES=$(echo "$resp" | jq -r '.data.user.contributionsCollection.totalIssueContributions // 0')
REVIEWS=$(echo "$resp" | jq -r '.data.user.contributionsCollection.totalPullRequestReviewContributions // 0')
STARS=$(echo "$resp" | jq -r '[.data.user.repositories.nodes[]?.stargazerCount // 0] | add // 0')
FORKS=$(echo "$resp" | jq -r '[.data.user.repositories.nodes[]?.forkCount // 0] | add // 0')

# Fetch recent activity
SINCE=$(date -d "$DAYS_BACK days ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -v-${DAYS_BACK}d '+%Y-%m-%dT%H:%M:%SZ')
EVENTS=$(gh_api "/users/$USERNAME/events?per_page=100")

ROWS=$(echo "$EVENTS" | jq -r --arg s "$SINCE" --arg user "$USERNAME" '
    [.[] | select(.created_at >= $s) |
     select(.type=="PushEvent" or .type=="PullRequestEvent" or
            .type=="CreateEvent" or .type=="IssuesEvent") |
     . + {is_own: (.repo.name | startswith($user + "/"))}] |
    sort_by([(.is_own | not), .created_at]) | reverse | .[0:10] |
    .[] |
    {
      date: (.created_at | split("T")[0]),
      type: .type,
      repo: .repo.name,
      repo_url: ("https://github.com/" + .repo.name),
      action: (if .type == "PushEvent" then "Push"
               elif .type == "PullRequestEvent" then "PR #" + (.payload.number // "?") + ": " + (.payload.action // "")
               elif .type == "CreateEvent" then "Created: " + (.payload.ref_type // "")
               elif .type == "IssuesEvent" then "Issue #" + (.payload.issue.number // "?") + ": " + (.payload.action // "")
               else .type end),
      detail: (if .type == "PushEvent" then (.payload.commits // [{}] | length | tostring) + " commit(s)"
               elif .type == "PullRequestEvent" then (.payload.pull_request.title // "Pull request" | .[0:60])
               elif .type == "CreateEvent" then (.payload.ref // "repository")
               elif .type == "IssuesEvent" then (.payload.issue.title // "Issue" | .[0:60])
               else "" end),
      icon: (if .type == "PushEvent" then "✅"
             elif .type == "PullRequestEvent" then "🔀"
             elif .type == "CreateEvent" then "🚀"
             elif .type == "IssuesEvent" then "🐛"
             else "📝" end)
    }' 2>/dev/null || echo "[]")

# Build table rows
TABLE_ROWS=""
while IFS= read -r row; do
    [[ "$row" == "null" || -z "$row" ]] && continue
    DATE=$(echo "$row" | jq -r '.date')
    REPO=$(echo "$row" | jq -r '.repo')
    REPO_URL=$(echo "$row" | jq -r '.repo_url')
    ACTION=$(echo "$row" | jq -r '.action')
    DETAIL=$(echo "$row" | jq -r '.detail')
    ICON=$(echo "$row" | jq -r '.icon')
    REPO_OWNER=$(echo "$REPO" | cut -d'/' -f1)
    REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)
    ENCODED=$(echo "$REPO_NAME" | sed 's/-/--/g')

    TABLE_ROWS+="  <tr>
    <td><strong>${DATE}</strong></td>
    <td><a href=\"${REPO_URL}\"><img src=\"https://img.shields.io/badge/${REPO_OWNER}-${ENCODED}-0366d6?style=flat&logo=github\" alt=\"${REPO}\"></a></td>
    <td><strong>${ACTION}</strong><br><small>${DETAIL}</small></td>
    <td>${ICON}</td>
  </tr>
"
done <<< "$ROWS"

if [[ -z "$TABLE_ROWS" ]]; then
    TABLE_ROWS="  <tr><td colspan=\"4\" align=\"center\"><em>No recent public activity</em></td></tr>"
fi

CURRENT_DATE=$(date '+%B %d, %Y')

# Patch README
python3 - "$README" "$REPOS" "$GISTS" "$FOLLOWERS" "$FOLLOWING" \
    "$COMMITS" "$PRS" "$ISSUES" "$REVIEWS" "$STARS" "$FORKS" \
    "$CURRENT_DATE" "$YEAR" "$DAYS_BACK" <<'PYEOF'
import re, sys

readme = open(sys.argv[1], encoding='utf-8').read()
repos, gists, followers, following = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
commits, prs, issues, reviews = sys.argv[6], sys.argv[7], sys.argv[8], sys.argv[9]
stars, forks, cur_date, year, days = sys.argv[10], sys.argv[11], sys.argv[12], sys.argv[13], sys.argv[14]

def patch(pat, repl, flags=0):
    global readme
    if re.search(pat, readme, flags):
        readme = re.sub(pat, repl, readme, count=1, flags=flags)
        return True
    return False

patch(r'Active_Contributor-\d{4}', f'Active_Contributor-{year}', flags=0)
patch(r'Public_Repos-32CD32.*?<strong>\d+</strong>', f'Public_Repos-32CD32?style=for-the-badge"><br><strong>{repos}</strong>')
patch(r'Gists-FFD700.*?<strong>\d+</strong>', f'Gists-FFD700?style=for-the-badge"><br><strong>{gists}</strong>')
patch(r'Issues-1E90FF.*?<strong>\d+</strong>', f'Issues-1E90FF?style=for-the-badge"><br><strong>{issues}</strong>')
patch(r'PR_Reviews-FF69B4.*?<strong>\d+</strong>', f'PR_Reviews-FF69B4?style=for-the-badge"><br><strong>{reviews}</strong>')
patch(r'Stars-FFD700.*?<strong>\d+</strong>', f'Stars-FFD700?style=for-the-badge"><br><strong>{stars}</strong>')
patch(r'Network-00D4AA.*?<strong>\d+ / \d+</strong>', f'Network-00D4AA?style=for-the-badge"><br><strong>{following} / {followers}</strong>')
patch(r'\| 🗂️ Public Repositories \| \*\*\d+\*\*', f'| 🗂️ Public Repositories | **{repos}** |')
patch(r'\| 📓 Public Gists \| \*\*\d+\*\*', f'| 📓 Public Gists | **{gists}** |')
patch(r'\| 👥 Followers \| \*\*\d+\*\*', f'| 👥 Followers | **{followers}** |')
patch(r'\| 🐣 Following \| \*\*\d+\*\*', f'| 🐣 Following | **{following}** |')
patch(r'\| ✨ Commits \(\d{4}\) \| \*\*\d+\*\*', f'| ✨ Commits ({year}) | **{commits}** |')
patch(r'\| 🔀 Pull Requests \| \*\*\d+\*\*', f'| 🔀 Pull Requests | **{prs}** |')
patch(r'\| 💡 Issues Opened \| \*\*\d+\*\*', f'| 💡 Issues Opened | **{issues}** |')
patch(r'\| 🔍 PR Reviews \| \*\*\d+\*\*', f'| 🔍 PR Reviews | **{reviews}** |')
patch(r'\| ⭐ Total Stars \| \*\*\d+\*\*', f'| ⭐ Total Stars | **{stars}** |')
patch(r'\| 🍴 Total Forks \| \*\*\d+\*\*', f'| 🍴 Total Forks | **{forks}** |')
patch(r'(Last updated: )[^\|]+(\|)', f'\\g<1>{cur_date} \\2', flags=0)

open(sys.argv[1], 'w', encoding='utf-8').write(readme)
print(f"Updated: repos={repos} commits={commits} prs={prs} stars={stars}")
PYEOF

echo "Done. Updated $README with latest stats."
