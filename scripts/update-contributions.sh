#!/bin/bash

# Auto-update README with recent GitHub contributions
# This script fetches recent commits, PRs, and updates the README.md file

set -e

# Configuration
USERNAME="yunus25jmi1"
README_FILE="README.md"
DAYS_BACK=7

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Get GitHub user statistics
get_github_stats() {
    log "Fetching GitHub statistics..."
    
    local user_data=$(curl -s "https://api.github.com/users/$USERNAME")
    TOTAL_REPOS=$(echo "$user_data" | jq -r '.public_repos // 0')
    FOLLOWERS=$(echo "$user_data" | jq -r '.followers // 0')
    FOLLOWING=$(echo "$user_data" | jq -r '.following // 0')
    
    log "Stats: $TOTAL_REPOS repos, $FOLLOWERS followers, $FOLLOWING following"
}

# Get recent activity from multiple sources
get_recent_activity() {
    log "Fetching recent activity..."
    
    local since_date=$(date -d "$DAYS_BACK days ago" '+%Y-%m-%dT%H:%M:%SZ')
    local contributions_html=""
    local total_commits=0
    local total_additions=0
    
    # Get events (includes pushes, PRs, etc.)
    local events=$(curl -s "https://api.github.com/users/$USERNAME/events?per_page=30")
    
    # Process events and create table rows
    echo "$events" | jq -r --arg since "$since_date" '
        .[] | 
        select(.created_at >= $since) |
        select(.type == "PushEvent" or .type == "PullRequestEvent" or .type == "CreateEvent") |
        {
            date: .created_at,
            type: .type,
            repo: .repo.name,
            repo_url: .repo.html_url,
            payload: .payload
        }' | jq -s '
        sort_by(.date) | reverse | .[0:10]
    ' > /tmp/recent_events.json
    
    # Convert events to HTML table rows
    local event_count=0
    while IFS= read -r event; do
        if [ "$event" != "null" ] && [ ! -z "$event" ]; then
            local date=$(echo "$event" | jq -r '.date')
            local type=$(echo "$event" | jq -r '.type')
            local repo=$(echo "$event" | jq -r '.repo')
            local repo_url=$(echo "$event" | jq -r '.repo_url')
            
            # Format date
            local formatted_date=$(date -d "$date" '+%b %d, %Y' 2>/dev/null || echo "Recent")
            
            # Determine activity details based on type
            local activity_desc=""
            local status_icon=""
            local repo_owner=$(echo "$repo" | cut -d'/' -f1)
            local repo_name=$(echo "$repo" | cut -d'/' -f2)
            
            case "$type" in
                "PushEvent")
                    local commits=$(echo "$event" | jq -r '.payload.commits | length')
                    activity_desc="<strong>Push:</strong> $commits commit(s)<br><small>Code updates and improvements</small>"
                    status_icon="�"
                    total_commits=$((total_commits + commits))
                    ;;
                "PullRequestEvent") 
                    local pr_action=$(echo "$event" | jq -r '.payload.action')
                    local pr_number=$(echo "$event" | jq -r '.payload.number // "N/A"')
                    activity_desc="<strong>PR #$pr_number:</strong> $pr_action<br><small>Pull request activity</small>"
                    status_icon="✅"
                    ;;
                "CreateEvent")
                    local ref_type=$(echo "$event" | jq -r '.payload.ref_type')
                    activity_desc="<strong>Created:</strong> New $ref_type<br><small>Repository or branch creation</small>"
                    status_icon="🚀"
                    ;;
                *)
                    activity_desc="<strong>Activity:</strong> $type<br><small>GitHub activity</small>"
                    status_icon="📝"
                    ;;
            esac
            
            # Add table row
            contributions_html+="  <tr>
    <td><strong>$formatted_date</strong></td>
    <td>
      <a href=\"$repo_url\">
        <img src=\"https://img.shields.io/badge/$repo_owner-$repo_name-0366d6?style=flat&logo=github\">
      </a>
    </td>
    <td>$activity_desc</td>
    <td>$status_icon</td>
  </tr>
"
            event_count=$((event_count + 1))
            
            # Limit to top 10 events
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
    TOTAL_COMMITS="$total_commits"
    
    log "Found $event_count recent activities with $total_commits commits"
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
    
    # Update recent contributions table
    python3 << EOF
import re

# Read the README file
with open('$README_FILE', 'r') as f:
    content = f.read()

# Define the new contributions table
new_table = '''#### 🚀 **Recent Contributions** (Last $DAYS_BACK Days)
<table width="100%">
  <tr>
    <th width="15%">Date</th>
    <th width="40%">Repository</th>
    <th width="30%">Contribution</th>
    <th width="15%">Status</th>
  </tr>
$RECENT_CONTRIBUTIONS</table>'''

# Find and replace the contributions table
pattern = r'#### � \*\*Recent Contributions\*\* \(Last \d+ Days?\).*?</table>'
content = re.sub(pattern, new_table, content, flags=re.DOTALL)

# Update contribution impact metrics
impact_section = '''#### �📈 **Contribution Impact**
<div align="center">
  <table>
    <tr>
      <td align="center">
        <img src="https://img.shields.io/badge/🔥-Recent_Activity-FF4500?style=for-the-badge">
        <br><strong>$TOTAL_COMMITS</strong><br><small>Last Week</small>
      </td>
      <td align="center">
        <img src="https://img.shields.io/badge/📝-Total_Repos-32CD32?style=for-the-badge">
        <br><strong>$TOTAL_REPOS</strong><br><small>Public</small>
      </td>
      <td align="center">
        <img src="https://img.shields.io/badge/🎯-Network-1E90FF?style=for-the-badge">
        <br><strong>$FOLLOWING/$FOLLOWERS</strong><br><small>Following/Followers</small>
      </td>
    </tr>
  </table>
</div>'''

# Replace contribution impact section
impact_pattern = r'#### 📈 \*\*Contribution Impact\*\*.*?</div>\s*</div>'
content = re.sub(impact_pattern, impact_section, content, flags=re.DOTALL)

# Update "Last Updated" timestamp
content = re.sub(
    r'\*\*Last Updated\*\*: [^|]+ \|',
    f'**Last Updated**: $current_date |',
    content
)

# Update quick highlights
highlights_pattern = r'(\*\*🔥 Current Streak\*\*\s*\n)(.*?)(\n\*\*🎓 Continuous Learning\*\*)'
new_highlights = '''**🔥 Current Streak**
- 💻 **$TOTAL_REPOS** total repositories
- 🔄 **$TOTAL_COMMITS** activities in last $DAYS_BACK days  
- 📈 Recent contributions tracked
- 🌟 **$FOLLOWING** following • **$FOLLOWERS** followers

**🎓 Continuous Learning**'''

content = re.sub(highlights_pattern, new_highlights, content, flags=re.DOTALL)

# Write the updated content
with open('$README_FILE', 'w') as f:
    f.write(content)

print("✅ README updated successfully!")
EOF
    
    log "README.md updated successfully!"
}

# Main execution
main() {
    log "🚀 Starting README auto-update..."
    
    if [ ! -f "$README_FILE" ]; then
        error "README.md not found!"
        exit 1
    fi
    
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
