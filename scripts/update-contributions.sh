#!/bin/bash

# Auto-update README with recent GitHub contributions
# This script fetches recent commits, PRs, and updates the README.md file

set -e

# Configuration
USERNAME="yunus25jmi1"
README_FILE="README.md"
DAYS_BACK=7

# GitHub token for private repos (optional, set as environment variable)
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Setup GitHub API headers
setup_auth_header() {
    if [ ! -z "$GITHUB_TOKEN" ]; then
        AUTH_HEADER="Authorization: token $GITHUB_TOKEN"
        log "Using authenticated API (includes private repos)"
    else
        AUTH_HEADER=""
        warn "No GITHUB_TOKEN set - only public contributions will be shown"
        warn "Set GITHUB_TOKEN environment variable to include private contributions"
    fi
}

# Get GitHub user statistics
get_github_stats() {
    log "Fetching GitHub statistics..."
    
    if [ ! -z "$AUTH_HEADER" ]; then
        local user_data=$(curl -s -H "$AUTH_HEADER" "https://api.github.com/user")
        local public_data=$(curl -s "https://api.github.com/users/$USERNAME")
    else
        local user_data=$(curl -s "https://api.github.com/users/$USERNAME")
        local public_data="$user_data"
    fi
    
    TOTAL_REPOS=$(echo "$public_data" | jq -r '.public_repos // 0')
    FOLLOWERS=$(echo "$public_data" | jq -r '.followers // 0')
    FOLLOWING=$(echo "$public_data" | jq -r '.following // 0')
    
    # Get private repo count if authenticated
    if [ ! -z "$AUTH_HEADER" ]; then
        TOTAL_PRIVATE_REPOS=$(echo "$user_data" | jq -r '.total_private_repos // 0')
        OWNED_PRIVATE_REPOS=$(echo "$user_data" | jq -r '.owned_private_repos // 0')
        log "Stats: $TOTAL_REPOS public repos, $OWNED_PRIVATE_REPOS private repos, $FOLLOWERS followers, $FOLLOWING following"
    else
        TOTAL_PRIVATE_REPOS=0
        OWNED_PRIVATE_REPOS=0
        log "Stats: $TOTAL_REPOS public repos, $FOLLOWERS followers, $FOLLOWING following"
    fi
}

# Get recent activity from multiple sources
get_recent_activity() {
    log "Fetching recent activity..."
    
    local since_date=$(date -d "$DAYS_BACK days ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -v-${DAYS_BACK}d '+%Y-%m-%dT%H:%M:%SZ')
    local since_date_iso=$(date -d "$DAYS_BACK days ago" -Iseconds 2>/dev/null || date -v-${DAYS_BACK}d -Iseconds)
    local contributions_html=""
    local total_commits=0
    
    # Get events (includes pushes, PRs, etc.) - authenticated calls show private events
    if [ ! -z "$AUTH_HEADER" ]; then
        local events=$(curl -s -H "$AUTH_HEADER" "https://api.github.com/users/$USERNAME/events?per_page=100")
    else
        local events=$(curl -s "https://api.github.com/users/$USERNAME/events?per_page=100")
    fi
    
    # Process events and create table rows
    echo "$events" | jq -r --arg since "$since_date" '
        .[] | 
        select(.created_at >= $since) |
        select(.type == "PushEvent" or .type == "PullRequestEvent" or .type == "CreateEvent" or .type == "IssuesEvent") |
        {
            date: .created_at,
            type: .type,
            repo: .repo.name,
            repo_url: ("https://github.com/" + .repo.name),
            payload: .payload
        }' | jq -s '
        sort_by(.date) | reverse | .[0:15]
    ' > /tmp/recent_events.json
    
    # Track unique repos for fetching commits
    declare -A repos_seen
    local total_commit_count=0
    
    # Convert events to HTML table rows
    local event_count=0
    while IFS= read -r event; do
        if [ "$event" != "null" ] && [ ! -z "$event" ]; then
            local date=$(echo "$event" | jq -r '.date')
            local type=$(echo "$event" | jq -r '.type')
            local repo=$(echo "$event" | jq -r '.repo')
            local repo_url=$(echo "$event" | jq -r '.repo_url')
            
            # Format date
            local formatted_date=$(date -d "$date" '+%b %d, %Y' 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$date" '+%b %d, %Y' 2>/dev/null || echo "Recent")
            
            # Determine activity details based on type
            local activity_desc=""
            local status_icon=""
            local repo_owner=$(echo "$repo" | cut -d'/' -f1)
            local repo_name=$(echo "$repo" | cut -d'/' -f2)
            
            # URL encode the repo name for badges (replace hyphens)
            local encoded_repo_name=$(echo "$repo_name" | sed 's/-/--/g')
            
            case "$type" in
                "PushEvent")
                    # Fetch actual commits from the repository
                    if [ -z "${repos_seen[$repo]}" ]; then
                        repos_seen[$repo]=1
                        
                        # Use authenticated API if token is available
                        if [ ! -z "$AUTH_HEADER" ]; then
                            local commits_data=$(curl -s -H "$AUTH_HEADER" "https://api.github.com/repos/$repo/commits?since=$since_date_iso&author=$USERNAME&per_page=100" 2>/dev/null)
                        else
                            local commits_data=$(curl -s "https://api.github.com/repos/$repo/commits?since=$since_date_iso&author=$USERNAME&per_page=100" 2>/dev/null)
                        fi
                        
                        local commit_count=$(echo "$commits_data" | jq '. | length' 2>/dev/null || echo "0")
                        local latest_commit_msg=$(echo "$commits_data" | jq -r '.[0].commit.message | split("\n")[0]' 2>/dev/null | head -c 80)
                        
                        # Check if repo is private
                        if [ ! -z "$AUTH_HEADER" ]; then
                            local repo_info=$(curl -s -H "$AUTH_HEADER" "https://api.github.com/repos/$repo" 2>/dev/null)
                            local is_private=$(echo "$repo_info" | jq -r '.private // false')
                        else
                            local is_private="false"
                        fi
                        
                        if [ ! -z "$latest_commit_msg" ] && [ "$latest_commit_msg" != "null" ] && [ "$commit_count" != "0" ]; then
                            if [ "$is_private" == "true" ]; then
                                activity_desc="<strong>Push:</strong> $commit_count commit(s) 🔒<br><small>$latest_commit_msg</small>"
                            else
                                activity_desc="<strong>Push:</strong> $commit_count commit(s)<br><small>$latest_commit_msg</small>"
                            fi
                            total_commit_count=$((total_commit_count + commit_count))
                        else
                            if [ "$is_private" == "true" ]; then
                                activity_desc="<strong>Push:</strong> Code updates 🔒<br><small>Private repository</small>"
                            else
                                activity_desc="<strong>Push:</strong> Code updates<br><small>Updated repository</small>"
                            fi
                            total_commit_count=$((total_commit_count + 1))
                        fi
                    else
                        # Already processed this repo
                        continue
                    fi
                    status_icon="✅"
                    total_commits=$((total_commits + 1))
                    ;;
                "PullRequestEvent") 
                    local pr_action=$(echo "$event" | jq -r '.payload.action')
                    local pr_number=$(echo "$event" | jq -r '.payload.number // "N/A"')
                    local pr_title=$(echo "$event" | jq -r '.payload.pull_request.title // "Pull request"' | head -c 60)
                    activity_desc="<strong>PR #$pr_number:</strong> $pr_action<br><small>$pr_title</small>"
                    status_icon="🔀"
                    total_commits=$((total_commits + 1))
                    ;;
                "CreateEvent")
                    local ref_type=$(echo "$event" | jq -r '.payload.ref_type')
                    local ref_name=$(echo "$event" | jq -r '.payload.ref // "repository"')
                    activity_desc="<strong>Created:</strong> New $ref_type<br><small>$ref_name</small>"
                    status_icon="🚀"
                    total_commits=$((total_commits + 1))
                    ;;
                "IssuesEvent")
                    local issue_action=$(echo "$event" | jq -r '.payload.action')
                    local issue_number=$(echo "$event" | jq -r '.payload.issue.number // "N/A"')
                    activity_desc="<strong>Issue #$issue_number:</strong> $issue_action<br><small>Issue activity</small>"
                    status_icon="🐛"
                    total_commits=$((total_commits + 1))
                    ;;
                *)
                    activity_desc="<strong>Activity:</strong> $type<br><small>GitHub activity</small>"
                    status_icon="📝"
                    total_commits=$((total_commits + 1))
                    ;;
            esac
            
            # Add table row with properly encoded badge
            contributions_html+="  <tr>
    <td><strong>$formatted_date</strong></td>
    <td>
      <a href=\"$repo_url\">
        <img src=\"https://img.shields.io/badge/$repo_owner-$encoded_repo_name-0366d6?style=flat&logo=github\" alt=\"$repo\">
      </a>
    </td>
    <td>$activity_desc</td>
    <td>$status_icon</td>
  </tr>
"
            event_count=$((event_count + 1))
            
            # Limit to top 10 unique events
            if [ $event_count -ge 10 ]; then
                break
            fi
        fi
    done < <(jq -c '.[]' /tmp/recent_events.json 2>/dev/null || echo "")
    
    # If no recent events, add a placeholder
    if [ -z "$contributions_html" ]; then
        contributions_html="  <tr>
    <td colspan=\"4\" align=\"center\">
      <em>🔍 No recent public activity in the last $DAYS_BACK days</em><br>
      <small>Private contributions or activity outside the timeframe may not be visible</small>
    </td>
  </tr>
"
        total_commits=0
    fi
    
    RECENT_CONTRIBUTIONS="$contributions_html"
    TOTAL_COMMITS="$total_commit_count"
    
    log "Found $event_count recent activities with $total_commit_count total commits"
}

# Update README with new data
update_readme() {
    log "Updating README.md..."
    
    local current_date=$(date '+%b %d, %Y')
    local current_year=$(date '+%Y')
    
    # Create backup
    cp "$README_FILE" "${README_FILE}.backup"
    
    # Update the contributions badges
    sed -i "s|Active_Contributor-[0-9]*|Active_Contributor-$current_year|g" "$README_FILE"
    sed -i "s|Total_PRs-[0-9]*+|Total_PRs-${TOTAL_COMMITS}+|g" "$README_FILE"
    
    # Build impact section with conditional private repos column
    local impact_section_middle=""
    if [ ! -z "$AUTH_HEADER" ] && [ "$OWNED_PRIVATE_REPOS" != "0" ]; then
        impact_section_middle="      <td align=\"center\">
        <img src=\"https://img.shields.io/badge/🔒-Private_Repos-9B59B6?style=for-the-badge\">
        <br><strong>$OWNED_PRIVATE_REPOS</strong><br><small>Private</small>
      </td>"
    fi
    
    # Use Python to update README sections
    python3 -c "
import re
import sys

# Read the README file
with open('$README_FILE', 'r', encoding='utf-8') as f:
    content = f.read()

# Define the new contributions table
new_table = '''#### 🚀 **Recent Contributions** (Last $DAYS_BACK Days)
<table width=\"100%\">
  <tr>
    <th width=\"15%\">Date</th>
    <th width=\"40%\">Repository</th>
    <th width=\"30%\">Contribution</th>
    <th width=\"15%\">Status</th>
  </tr>
$RECENT_CONTRIBUTIONS</table>'''

# Find and replace the contributions table (flexible pattern to match any emoji)
pattern = r'#### .{1,3} ?\*\*Recent Contributions\*\* \(Last \d+ Days?\).*?</table>'
matches = re.findall(pattern, content, flags=re.DOTALL)
if matches:
    content = re.sub(pattern, new_table, content, flags=re.DOTALL)
    print('✅ Updated Recent Contributions table')
else:
    print('⚠️  Could not find Recent Contributions section')

# Update contribution impact metrics
impact_section = '''#### 📈 **Contribution Impact**
<div align=\"center\">
  <table>
    <tr>
      <td align=\"center\">
        <img src=\"https://img.shields.io/badge/🔥-Total_Commits-FF4500?style=for-the-badge\">
        <br><strong>$TOTAL_COMMITS</strong><br><small>Last 7 Days</small>
      </td>
      <td align=\"center\">
        <img src=\"https://img.shields.io/badge/📝-Public_Repos-32CD32?style=for-the-badge\">
        <br><strong>$TOTAL_REPOS</strong><br><small>Public</small>
      </td>
$impact_section_middle
      <td align=\"center\">
        <img src=\"https://img.shields.io/badge/🎯-Network-1E90FF?style=for-the-badge\">
        <br><strong>$FOLLOWING/$FOLLOWERS</strong><br><small>Following/Followers</small>
      </td>
    </tr>
  </table>
</div>'''

# Replace contribution impact section
impact_pattern = r'#### 📈 \*\*Contribution Impact\*\*.*?</table>\s*</div>'
if re.search(impact_pattern, content, flags=re.DOTALL):
    content = re.sub(impact_pattern, impact_section, content, flags=re.DOTALL)
    print('✅ Updated Contribution Impact section')
else:
    print('⚠️  Could not find Contribution Impact section')

# Update \"Last Updated\" timestamp
last_updated_pattern = r'\*\*Last Updated\*\*: [^|]+ \|'
if re.search(last_updated_pattern, content):
    content = re.sub(last_updated_pattern, '**Last Updated**: $current_date |', content)
    print('✅ Updated Last Updated timestamp')
else:
    print('⚠️  Could not find Last Updated timestamp')

# Update quick highlights in About Me section
highlights_pattern = r'(\*\*🔥 Current Streak\*\*\s*\n)(- .*?\n)+(- .*?\n)*(\*\*🎓 Continuous Learning\*\*)'
new_highlights = '''**🔥 Current Streak**
- 💻 **$TOTAL_REPOS** total repositories
- 🔄 **$TOTAL_COMMITS** activities in last $DAYS_BACK days  
- 📈 Recent contributions tracked
- 🌟 **$FOLLOWING** following • **$FOLLOWERS** followers

**🎓 Continuous Learning**'''

if re.search(highlights_pattern, content, flags=re.DOTALL):
    content = re.sub(highlights_pattern, new_highlights, content, flags=re.DOTALL)
    print('✅ Updated Current Streak section')
else:
    print('⚠️  Could not find Current Streak section')

# Write the updated content
with open('$README_FILE', 'w', encoding='utf-8') as f:
    f.write(content)

print('✅ README updated successfully!')
"
    
    log "README.md updated successfully!"
}

# Main execution
main() {
    log "🚀 Starting README auto-update..."
    
    if [ ! -f "$README_FILE" ]; then
        error "README.md not found!"
        exit 1
    fi
    
    # Setup authentication
    setup_auth_header
    
    # Fetch data
    get_github_stats
    get_recent_activity
    
    # Update README
    update_readme
    
    # Cleanup
    rm -f /tmp/recent_events.json
    
    log "🎉 Auto-update completed successfully!"
}

# Run main function
main "$@"
