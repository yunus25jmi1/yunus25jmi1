#!/bin/bash

# =============================================================================
# Auto-update README with GitHub statistics & recent contributions
# Sections updated:
#   - 📈 Contribution Impact (live counters)
#   - 📊 Live Stats Dashboard (GitHub side)
#   - 📊 Detailed Analytics badges
#   - 🏆 Achievement Highlights bullet list
#   - 🚀 Recent Contributions table (last N days)
#   - Active_Contributor badge year
#   - 🕒 Footer "Last updated" line
# =============================================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
USERNAME="yunus25jmi1"
README_FILE="README.md"
DAYS_BACK=7
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# ── Helpers ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()   { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
info()  { echo -e "${BLUE}[INFO]${NC} $1"; }

# ── Auth ──────────────────────────────────────────────────────────────────────
setup_auth() {
    if [[ -n "$GITHUB_TOKEN" ]]; then
        log "Authenticated – private data included"
    else
        warn "No GITHUB_TOKEN – public data only"
    fi
}

# Wrapper: use gh CLI if available, else curl
gh_api() {
    local endpoint="$1"
    if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
        gh api "$endpoint" 2>/dev/null
    elif [[ -n "$GITHUB_TOKEN" ]]; then
        curl -sf -H "Authorization: Bearer $GITHUB_TOKEN" \
             -H "Accept: application/vnd.github.v3+json" \
             "https://api.github.com${endpoint}"
    else
        curl -sf -H "Accept: application/vnd.github.v3+json" \
             "https://api.github.com${endpoint}"
    fi
}

# ── 1. Profile stats ──────────────────────────────────────────────────────────
fetch_profile_stats() {
    log "Fetching profile stats..."
    local data
    data=$(gh_api "/users/$USERNAME")

    TOTAL_REPOS=$(echo "$data"  | jq -r '.public_repos  // 0')
    PUBLIC_GISTS=$(echo "$data" | jq -r '.public_gists  // 0')
    FOLLOWERS=$(echo "$data"    | jq -r '.followers     // 0')
    FOLLOWING=$(echo "$data"    | jq -r '.following     // 0')

    log "Repos=$TOTAL_REPOS  Gists=$PUBLIC_GISTS  Followers=$FOLLOWERS  Following=$FOLLOWING"
}

# ── 2. Contribution stats via GraphQL ─────────────────────────────────────────
fetch_contribution_stats() {
    log "Fetching contribution stats via GraphQL..."

    local CURRENT_YEAR FROM_ISO TO_ISO
    CURRENT_YEAR=$(date '+%Y')
    FROM_ISO="${CURRENT_YEAR}-01-01T00:00:00Z"
    TO_ISO=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    local GQL='query($login:String!,$from:DateTime!,$to:DateTime!){
      user(login:$login){
        repositories(first:100,ownerAffiliations:OWNER){
          totalCount
          nodes{stargazerCount forkCount}
        }
        contributionsCollection(from:$from,to:$to){
          totalCommitContributions
          totalPullRequestContributions
          totalIssueContributions
          totalPullRequestReviewContributions
          restrictedContributionsCount
        }
      }
    }'

    local resp="{}"
    if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
        resp=$(gh api graphql \
            -f query="$GQL" \
            -f login="$USERNAME" \
            -f from="$FROM_ISO" \
            -f to="$TO_ISO" 2>/dev/null || echo "{}")
    elif [[ -n "$GITHUB_TOKEN" ]]; then
        local payload
        payload=$(python3 -c "
import json, sys
q=sys.stdin.read()
print(json.dumps({'query':q,'variables':{'login':'$USERNAME','from':'$FROM_ISO','to':'$TO_ISO'}}))
" <<< "$GQL")
        resp=$(curl -sf -H "Authorization: Bearer $GITHUB_TOKEN" \
                    -H "Content-Type: application/json" \
                    -d "$payload" "https://api.github.com/graphql" 2>/dev/null || echo "{}")
    fi

    COMMITS_YTD=$(echo "$resp"  | jq -r '.data.user.contributionsCollection.totalCommitContributions                // 0')
    PRS_YTD=$(echo "$resp"      | jq -r '.data.user.contributionsCollection.totalPullRequestContributions          // 0')
    ISSUES_YTD=$(echo "$resp"   | jq -r '.data.user.contributionsCollection.totalIssueContributions                // 0')
    REVIEWS_YTD=$(echo "$resp"  | jq -r '.data.user.contributionsCollection.totalPullRequestReviewContributions    // 0')
    PRIVATE_CONTRIBS=$(echo "$resp" | jq -r '.data.user.contributionsCollection.restrictedContributionsCount       // 0')
    TOTAL_STARS=$(echo "$resp"  | jq -r   '[.data.user.repositories.nodes[]?.stargazerCount // 0] | add // 0')
    TOTAL_FORKS=$(echo "$resp"  | jq -r   '[.data.user.repositories.nodes[]?.forkCount      // 0] | add // 0')
    REPO_COUNT_GQL=$(echo "$resp" | jq -r '.data.user.repositories.totalCount               // 0')
    TOTAL_ACTIVITIES_YTD=$(( COMMITS_YTD + PRS_YTD + ISSUES_YTD + REVIEWS_YTD ))

    log "YTD commits=$COMMITS_YTD  PRs=$PRS_YTD  issues=$ISSUES_YTD  reviews=$REVIEWS_YTD"
}

# ── 3. Recent activity (last DAYS_BACK days) ──────────────────────────────────
fetch_recent_activity() {
    log "Fetching recent activity (last $DAYS_BACK days)..."

    local SINCE_DATE SINCE_ISO
    SINCE_DATE=$(date -d "$DAYS_BACK days ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
              || date -v-${DAYS_BACK}d '+%Y-%m-%dT%H:%M:%SZ')
    SINCE_ISO=$(date -d "$DAYS_BACK days ago" -Iseconds 2>/dev/null \
             || date -v-${DAYS_BACK}d -Iseconds)

    local events
    events=$(gh_api "/users/$USERNAME/events?per_page=100")

    TOTAL_ACTIVITIES=$(echo "$events" | jq -r --arg s "$SINCE_DATE" '
        [.[] | select(.created_at >= $s) |
         select(.type=="PushEvent" or .type=="PullRequestEvent" or
                .type=="CreateEvent" or .type=="IssuesEvent")] | length')

    echo "$events" | jq -r --arg s "$SINCE_DATE" --arg user "$USERNAME" '
        [.[] | select(.created_at >= $s) |
         select(.type=="PushEvent" or .type=="PullRequestEvent" or
                .type=="CreateEvent" or .type=="IssuesEvent") |
         . + {is_own_repo: (.repo.name | startswith($user + "/"))}] |
        sort_by([(.is_own_repo | not), .created_at]) | reverse | .[0:20]' > /tmp/recent_events.json

    declare -A REPOS_SEEN
    local contributions_html="" event_count=0

    while IFS= read -r event; do
        [[ "$event" == "null" || -z "$event" ]] && continue

        local date type repo repo_url
        date=$(echo "$event"     | jq -r '.date')
        type=$(echo "$event"     | jq -r '.type')
        repo=$(echo "$event"     | jq -r '.repo')
        repo_url=$(echo "$event" | jq -r '.repo_url')

        local formatted_date
        formatted_date=$(date -d "$date" '+%b %d, %Y' 2>/dev/null \
                        || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$date" '+%b %d, %Y' 2>/dev/null \
                        || echo "Recent")

        local repo_owner repo_name encoded_repo activity_desc status_icon
        repo_owner=$(echo "$repo" | cut -d'/' -f1)
        repo_name=$(echo "$repo"  | cut -d'/' -f2)
        encoded_repo=$(echo "$repo_name" | sed 's/-/--/g')

        case "$type" in
            PushEvent)
                [[ -v REPOS_SEEN["$repo"] ]] && continue
                REPOS_SEEN["$repo"]=1
                local commits_data commit_count latest_msg
                commits_data=$(gh_api "/repos/$repo/commits?since=${SINCE_ISO}&author=${USERNAME}&per_page=100" 2>/dev/null || echo "[]")
                commit_count=$(echo "$commits_data" | jq 'length // 0')
                latest_msg=$(echo "$commits_data"   | jq -r '.[0].commit.message // ""' | head -c 80 | head -1)
                [[ "$commit_count" == "0" ]] && commit_count=1
                [[ -z "$latest_msg" || "$latest_msg" == "null" ]] && latest_msg="Updated repository"
                activity_desc="<strong>Push:</strong> ${commit_count} commit(s)<br><small>${latest_msg}</small>"
                status_icon="✅"
                ;;
            PullRequestEvent)
                local pr_action pr_num pr_title
                pr_action=$(echo "$event" | jq -r '.payload.action')
                pr_num=$(echo "$event"    | jq -r '.payload.number // "N/A"')
                pr_title=$(echo "$event"  | jq -r '.payload.pull_request.title // "Pull request"' | head -c 60)
                activity_desc="<strong>PR #${pr_num}:</strong> ${pr_action}<br><small>${pr_title}</small>"
                status_icon="🔀"
                ;;
            CreateEvent)
                local ref_type ref_name
                ref_type=$(echo "$event" | jq -r '.payload.ref_type')
                ref_name=$(echo "$event" | jq -r '.payload.ref // "repository"')
                activity_desc="<strong>Created:</strong> New ${ref_type}<br><small>${ref_name}</small>"
                status_icon="🚀"
                ;;
            IssuesEvent)
                local iss_action iss_num
                iss_action=$(echo "$event" | jq -r '.payload.action')
                iss_num=$(echo "$event"    | jq -r '.payload.issue.number // "N/A"')
                activity_desc="<strong>Issue #${iss_num}:</strong> ${iss_action}<br><small>Issue activity</small>"
                status_icon="🐛"
                ;;
            *)
                activity_desc="<strong>Activity:</strong> ${type}<br><small>GitHub activity</small>"
                status_icon="📝"
                ;;
        esac

        contributions_html+="  <tr>
    <td><strong>${formatted_date}</strong></td>
    <td>
      <a href=\"${repo_url}\">
        <img src=\"https://img.shields.io/badge/${repo_owner}-${encoded_repo}-0366d6?style=flat&logo=github\" alt=\"${repo}\">
      </a>
    </td>
    <td>${activity_desc}</td>
    <td>${status_icon}</td>
  </tr>
"
        event_count=$(( event_count + 1 ))
        (( event_count >= 10 )) && break

    done < <(jq -c '[.[] | {date:.created_at, type:.type, repo:.repo.name,
                            repo_url:("https://github.com/"+.repo.name),
                            payload:.payload}] | .[]' /tmp/recent_events.json 2>/dev/null || true)

    if [[ -z "$contributions_html" ]]; then
        contributions_html="  <tr>
    <td colspan=\"4\" align=\"center\">
      <em>🔍 No recent public activity in the last ${DAYS_BACK} days</em>
    </td>
  </tr>
"
    fi

    RECENT_CONTRIBUTIONS_HTML="$contributions_html"
    log "Recent rows=$event_count  window_activities=$TOTAL_ACTIVITIES"
}

# ── 4. Patch README via Python ────────────────────────────────────────────────
# NOTE: heredoc is QUOTED (<<'PYEOF') so bash NEVER interprets its contents.
#       All values are passed via exported env-vars to avoid any substitution.
update_readme() {
    log "Patching README.md..."

    local CURRENT_DATE CURRENT_YEAR EFFECTIVE_REPOS
    CURRENT_DATE=$(date '+%B %d, %Y')
    CURRENT_YEAR=$(date '+%Y')
    EFFECTIVE_REPOS="${REPO_COUNT_GQL:-$TOTAL_REPOS}"

    printf '%s' "$RECENT_CONTRIBUTIONS_HTML" > /tmp/readme_html_rows.txt
    cp "$README_FILE" "${README_FILE}.backup"

    # Export everything Python needs via env-vars (no shell expansion in heredoc)
    export _README="$README_FILE"
    export _REPOS="$EFFECTIVE_REPOS"
    export _GISTS="$PUBLIC_GISTS"
    export _FOLLOWERS="$FOLLOWERS"
    export _FOLLOWING="$FOLLOWING"
    export _COMMITS="$COMMITS_YTD"
    export _PRS="$PRS_YTD"
    export _ISSUES="$ISSUES_YTD"
    export _REVIEWS="$REVIEWS_YTD"
    export _STARS="$TOTAL_STARS"
    export _FORKS="$TOTAL_FORKS"
    export _DATE="$CURRENT_DATE"
    export _YEAR="$CURRENT_YEAR"
    export _DAYS="$DAYS_BACK"

    # Write medium articles JSON to temp file (too large for env var)
    printf '%s' "${MEDIUM_ARTICLES_JSON:-[]}" > /tmp/medium_articles.json

    python3 - <<'PYEOF'
import re, os

readme   = open(os.environ['_README'], encoding='utf-8').read()
html_rows = open('/tmp/readme_html_rows.txt', encoding='utf-8').read()
changes  = []

repos     = os.environ['_REPOS']
gists     = os.environ['_GISTS']
followers = os.environ['_FOLLOWERS']
following = os.environ['_FOLLOWING']
commits   = os.environ['_COMMITS']
prs       = os.environ['_PRS']
issues    = os.environ['_ISSUES']
reviews   = os.environ['_REVIEWS']
stars     = os.environ['_STARS']
forks     = os.environ['_FORKS']
cur_date  = os.environ['_DATE']
cur_year  = os.environ['_YEAR']
days_back = os.environ['_DAYS']

def patch(label, pattern, replacement='__SKIP__', flags=re.DOTALL):
    global readme
    if replacement == '__SKIP__':
        return bool(re.search(pattern, readme, flags=flags))
    if re.search(pattern, readme, flags=flags):
        readme = re.sub(pattern, replacement, readme, count=1, flags=flags)
        changes.append('✅ ' + label)
        return True
    changes.append('⚠️  NOT FOUND: ' + label)
    return False

# ── 1. Active Contributor badge year ─────────────────────────────────────────
patch('Active_Contributor badge year',
      r'Active_Contributor-\d{4}',
      f'Active_Contributor-{cur_year}',
      flags=0)

# ── 2. Recent Contributions table ────────────────────────────────────────────
new_table = (
    f"#### 🚀 **Recent Contributions** (Last {days_back} Days)\n"
    '<table width="100%">\n'
    '  <tr>\n'
    '    <th width="15%">Date</th>\n'
    '    <th width="40%">Repository</th>\n'
    '    <th width="30%">Contribution</th>\n'
    '    <th width="15%">Status</th>\n'
    '  </tr>\n'
    f'{html_rows}</table>'
)
patch('Recent Contributions table',
      r'#### .{1,3}\s*\*\*Recent Contributions\*\*.*?</table>',
      new_table)

# ── 3. Contribution Impact counters (8 cells) ────────────────────────────────
new_impact = (
    f"#### 📈 **Contribution Impact** <sub>*(fetched via gh CLI · {cur_date})*</sub>\n"
    '<div align="center">\n'
    '  <table>\n'
    '    <tr>\n'
    f'      <td align="center"><img src="https://img.shields.io/badge/%F0%9F%94%A5-Commits_({cur_year})-FF4500?style=for-the-badge"><br><strong>{commits}</strong><br><small>This year</small></td>\n'
    f'      <td align="center"><img src="https://img.shields.io/badge/%F0%9F%94%80-Pull_Requests-8A2BE2?style=for-the-badge"><br><strong>{prs}</strong><br><small>Total PRs</small></td>\n'
    f'      <td align="center"><img src="https://img.shields.io/badge/%F0%9F%93%9D-Public_Repos-32CD32?style=for-the-badge"><br><strong>{repos}</strong><br><small>Public</small></td>\n'
    f'      <td align="center"><img src="https://img.shields.io/badge/%F0%9F%93%9A-Gists-FFD700?style=for-the-badge"><br><strong>{gists}</strong><br><small>Public Gists</small></td>\n'
    f'      <td align="center"><img src="https://img.shields.io/badge/%F0%9F%8E%AF-Issues-1E90FF?style=for-the-badge"><br><strong>{issues}</strong><br><small>This year</small></td>\n'
    f'      <td align="center"><img src="https://img.shields.io/badge/%F0%9F%94%8D-PR_Reviews-FF69B4?style=for-the-badge"><br><strong>{reviews}</strong><br><small>Reviews</small></td>\n'
    f'      <td align="center"><img src="https://img.shields.io/badge/%E2%AD%90-Stars-FFD700?style=for-the-badge"><br><strong>{stars}</strong><br><small>Stars earned</small></td>\n'
    f'      <td align="center"><img src="https://img.shields.io/badge/%F0%9F%91%A5-Network-00D4AA?style=for-the-badge"><br><strong>{following} / {followers}</strong><br><small>Following / Followers</small></td>\n'
    '    </tr>\n'
    '  </table>\n'
    '</div>'
)
patch('Contribution Impact section',
      r'#### 📈 \*\*Contribution Impact\*\*.*?</table>\s*</div>',
      new_impact)

# ── 4. Live Stats Dashboard – GitHub table ───────────────────────────────────
# ROOT-CAUSE FIX: end match with [^\n]+ so it never accumulates duplicate cells
github_rows = (
    "| Metric | Value |\n"
    "|--------|-------|\n"
    f"| 🗂️ Public Repositories | **{repos}** |\n"
    f"| 📓 Public Gists | **{gists}** |\n"
    f"| 👥 Followers | **{followers}** |\n"
    f"| 🐣 Following | **{following}** |\n"
    f"| ✨ Commits ({cur_year}) | **{commits}** |\n"
    f"| 🔀 Pull Requests | **{prs}** |\n"
    f"| 💡 Issues Opened | **{issues}** |\n"
    f"| 🔍 PR Reviews | **{reviews}** |\n"
    f"| ⭐ Total Stars | **{stars}** |\n"
    f"| 🍴 Total Forks | **{forks}** |\n"
    f"| 📅 Member Since | **Oct 2022** |"
)
patch('Live Stats Dashboard GitHub table',
      r'(### ⚫ \*\*GitHub Stats\*\*.*?<sub><em>via gh CLI</em></sub>\s*\n\s*\n)'
      r'\| Metric \| Value \|.*?\| 📅 Member Since[^\n]+',
      r'\g<1>' + github_rows)

# ── 5. Detailed Analytics badges ─────────────────────────────────────────────
patch('Total_Repositories badge',
      r'Total_Repositories-\d+',
      f'Total_Repositories-{repos}', flags=0)

patch('Public_Gists badge',
      r'Public_Gists-\d+',
      f'Public_Gists-{gists}', flags=0)

patch('Network badge',
      r'Network-\d+_Following_%E2%80%A2_\d+_Followers-4ECDC4',
      f'Network-{following}_Following_%E2%80%A2_{followers}_Followers-4ECDC4',
      flags=0)

# ── 6. Achievement Highlights bullets ────────────────────────────────────────
patch('Achievement Highlights – repo count',
      r'(🔥 \*\*GitHub Journey\*\*: Started October 2022, now )\d+\+',
      r'\g<1>' + repos + r'+', flags=0)

patch('Achievement Highlights – LinkedIn line',
      r'(📅 \*\*Consistent Growth\*\*: ).*',
      r'\g<1>2,328 LinkedIn followers, 500+ connections, 1,967 profile views',
      flags=0)

# ── 7. LinkedIn Stats date ────────────────────────────────────────────────────
patch('LinkedIn Stats date',
      r'(<sub><em>as of )[^<]+(</em></sub>)',
      r'\g<1>' + cur_date + r'\2', flags=0)

# ── 8. Long-term Statistics diff block (wholesale replace) ───────────────────
fence = '```'
new_diff = (
    f'{fence}diff\n'
    f'+ {repos}+ Total Public Repositories\n'
    f'+ 57 Total Skills on LinkedIn\n'
    f'+ {following} Following • {followers} Followers\n'
    '+ 99.9% Infrastructure uptime achieved\n'
    f'+ {gists} Public Gists created\n'
    '+ Active since October 2022\n'
    f'+ {stars} Total Stars across repositories\n'
    f'+ {forks} Total Forks\n'
    '+ 12 Technical Publications on YunusCloud\n'
    '+ 53 Professional Certifications\n'
    f'{fence}'
)
patch('Long-term Statistics diff block',
      fence + r'diff.*?' + fence,
      new_diff)

# ── 9. Footer timestamps ─────────────────────────────────────────────────────
patch('Footer Last Updated',
      r'(Last updated: )[^\|<\n]+(\|)',
      r'\g<1>' + cur_date + r' \2', flags=0)

patch('Sub footer timestamp',
      r'(🕒 Last updated: )[^\|]+(\|)',
      r'\g<1>' + cur_date + r' \2', flags=0)


# ── 10. Medium Blog section (from RSS feed) ──────────────────────────────────
try:
    import json as _json
    articles = _json.loads(open('/tmp/medium_articles.json').read())
except Exception:
    articles = []

if articles:
    # Tag → emoji mapping
    TAG_EMOJI = {
        'kubernetes': '☸️', 'k8s': '☸️', 'docker': '🐳',
        'oracle-cloud': '🔶', 'oci': '🔶',
        'devops': '⚙️', 'devsecops': '🔒', 'ci-cd': '🔄',
        'security': '🛡️', 'cybersecurity': '🛡️',
        'cloud-architecture': '🏗️', 'cloud-computing': '☁️',
        'terraform': '🌍', 'ansible': '🤖',
        'microservices': '🔗', 'distributed-systems': '🌐',
        'site-reliability-engineer': '📊', 'observability': '🔍',
        'kafka': '📨', 'scalability': '📈',
        'java': '☕', 'python': '🐍',
        'machine-learning': '🤖', 'ai': '🤖',
        'system-design-concepts': '📐', 'cloud-native': '🚀',
        'multitenancy': '👥', 'disaster-recovery': '🔥',
        'kubernetes-cluster': '☸️'
    }

    def get_emoji(tags):
        for t in tags:
            e = TAG_EMOJI.get(t.lower())
            if e: return e
        return '📝'

    def badge_url(tag):
        t = tag.replace('-', '_').replace(' ', '_')[:20]
        return f'https://img.shields.io/badge/{t}-555?style=flat-square&logo=medium&logoColor=white&labelColor=00AB6C'

    # Split into two columns (left: odds, right: evens)
    left  = articles[::2]   # indices 0,2,4,6,8
    right = articles[1::2]  # indices 1,3,5,7,9

    def render_col(arts):
        out = ''
        for a in arts:
            emoji = get_emoji(a['tags'])
            title = a['title'][:75] + ('…' if len(a['title'])>75 else '')
            tag_badges = ' '.join(
                f'<img src="{badge_url(t)}" height="14">'
                for t in a['tags'][:2]
            )
            out += (
                f'- {emoji} [**{title}**]({a["link"]})\n'
                f'  <br><sub>📅 {a["date"]} &nbsp;{tag_badges}</sub>\n\n'
            )
        return out.rstrip()

    new_blog = (
        '<!-- Medium Blog -->\n'
        '<h2 align="center">✍️ Latest Technical Writing</h2>\n\n'
        '<div align="center">\n'
        '  <img src="https://img.shields.io/badge/Platform-Medium-00AB6C?style=for-the-badge&logo=medium&logoColor=white">\n'
        '  <img src="https://img.shields.io/badge/Focus-Kubernetes_%7C_Cloud_%7C_DevOps-4ECDC4?style=for-the-badge">\n'
        '</div>\n\n'
        '<br>\n\n'
        '<table width="100%">\n<tr>\n<td width="50%" valign="top">\n\n'
        + render_col(left)
        + '\n\n</td>\n<td width="50%" valign="top">\n\n'
        + render_col(right)
        + '\n\n</td>\n</tr>\n</table>\n\n'
        '<div align="center">\n'
        '<a href="https://cloudrelic.medium.com">\n'
        '  <img src="https://img.shields.io/badge/Read_More_on_Medium-00AB6C?style=for-the-badge&logo=medium&logoColor=white">\n'
        '</a>\n'
        '</div>'
    )
    patch('Medium Blog section',
          r'<!-- Medium Blog -->.*?</div>(?=\s*\n\s*---\s*\n\s*<!-- Connect)',
          new_blog)
else:
    changes.append('⚠️  SKIPPED: Medium Blog section (no articles fetched)')

open(os.environ['_README'], 'w', encoding='utf-8').write(readme)

ok  = sum(1 for c in changes if c.startswith('✅'))
bad = sum(1 for c in changes if c.startswith('⚠'))
for c in changes:
    print(c)
print(f"\n✨ {ok} sections updated · {bad} not found")
PYEOF

    log "README.md patched."
}


# ── 5. Medium RSS feed ────────────────────────────────────────────────────────
fetch_medium_articles() {
    log "Fetching Medium RSS feed..."
    local RSS_URL="https://cloudrelic.medium.com/feed"

    if ! curl -sfL --max-time 15 "$RSS_URL" -o /tmp/medium_feed.xml 2>/dev/null; then
        warn "Medium RSS fetch failed – blog section unchanged"
        MEDIUM_ARTICLES_JSON="[]"
        return
    fi

    MEDIUM_ARTICLES_JSON=$(python3 - << 'PYPARSE'
import re, json, html
from datetime import datetime

data = open('/tmp/medium_feed.xml', encoding='utf-8').read()
items = re.findall(r'<item>(.*?)</item>', data, re.DOTALL)

articles = []
for item in items[:10]:
    def xt(tag):
        m = (re.search(rf'<{tag}><!\[CDATA\[(.*?)\]\]></{tag}>', item, re.DOTALL)
          or re.search(rf'<{tag}>(.*?)</{tag}>', item, re.DOTALL))
        return html.unescape(m.group(1).strip()) if m else ''
    title = xt('title')
    link  = xt('link') or xt('guid')
    raw_d = xt('pubDate')[:16].strip()
    cats  = re.findall(r'<category><!\[CDATA\[(.*?)\]\]></category>', item)
    for fmt in ('%a, %d %b %Y %H:%M', '%a, %d %b %Y'):
        try: raw_d = datetime.strptime(raw_d, fmt).strftime('%b %d, %Y'); break
        except ValueError: pass
    articles.append({'title': title, 'link': link, 'date': raw_d, 'tags': cats})

print(json.dumps(articles))
PYPARSE
)

    log "Medium: $(echo "$MEDIUM_ARTICLES_JSON" | python3 -c "import json,sys; print(len(json.load(sys.stdin)),'articles')")"
}


# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    log "🚀 Starting README auto-update..."
    [[ -f "$README_FILE" ]] || { error "README.md not found!"; exit 1; }

    setup_auth
    fetch_profile_stats
    fetch_contribution_stats
    fetch_recent_activity
    fetch_medium_articles
    update_readme

    rm -f /tmp/recent_events.json /tmp/readme_html_rows.txt /tmp/medium_feed.xml /tmp/medium_articles.json
    log "🎉 All done!"
}

main "$@"
