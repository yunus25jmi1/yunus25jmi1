# 🤖 Automated README Update System

This system automatically updates your GitHub profile README with recent contributions, statistics, and activity.

## 📁 Files Overview

### 🔧 Scripts
- **`scripts/update-contributions.sh`** - Main update script that fetches GitHub data and updates README
- **`test-setup.sh`** - Test script to validate the setup

### ⚙️ GitHub Actions
- **`.github/workflows/update-readme.yml`** - Automated workflow that runs the update script

## 🚀 How It Works

### 1. **Data Collection**
The script fetches:
- Recent GitHub activity (commits, PRs, pushes)
- Repository statistics (total repos, followers, following)
- User profile information

### 2. **README Updates**
Updates these sections automatically:
- 🌟 **Open Source Contributions** - Recent activity table
- 📈 **Contribution Impact** - Statistics and metrics  
- 🔥 **Current Streak** - Repository and network stats
- ⏰ **Last Updated** - Timestamp

### 3. **Automation Schedule**
Runs automatically:
- 📅 **Daily at 6:00 AM UTC** (11:30 AM IST)
- 🔄 **On every push** to main branch
- 🎯 **Manual trigger** available

## 🛠️ Setup Instructions

### 1. **Install & Test**
```bash
# Make test script executable
chmod +x test-setup.sh

# Run the setup test
./test-setup.sh
```

### 2. **Commit Files**
```bash
git add scripts/ .github/ test-setup.sh
git commit -m "🤖 Add automated README update system"
git push origin main
```

### 3. **Verify Workflow**
- Go to your repository's **Actions** tab
- You should see the "🔄 Auto-Update README Contributions" workflow
- It will run automatically or can be triggered manually

## 📊 What Gets Updated

### Recent Contributions Table
- ✅ Last 7 days of activity
- 📝 Commit messages and details
- 🔗 Repository links with badges
- 📈 Activity type and status

### Statistics Badges
- 📊 Total repository count
- 👥 Followers/Following count
- 🔥 Recent activity count
- 📅 Current year badge

### Quick Highlights
- 💻 Repository statistics
- 🔄 Recent activity summary
- 📈 Contribution metrics
- 🌟 Network information

## 🔧 Customization

### Modify Update Frequency
Edit `.github/workflows/update-readme.yml`:
```yaml
schedule:
  # Change cron expression for different timing
  - cron: '0 6 * * *'  # Daily at 6 AM UTC
```

### Adjust Activity Period
Edit `scripts/update-contributions.sh`:
```bash
# Change number of days to look back
DAYS_BACK=7  # Change to 14, 30, etc.
```

### Customize Content
The script uses these sections in your README:
- Look for `<!-- Open Source Contributions -->` comment
- Updates content between markers automatically
- Preserves other sections unchanged

## 🔍 Troubleshooting

### Common Issues

**1. Script Not Running**
- Check if files have execute permissions
- Verify GitHub Actions is enabled in repository settings

**2. No Updates Appearing**
- Check if you have recent public activity
- Private repository activity won't be visible
- Verify the date range in script settings

**3. API Rate Limits**
- GitHub API has rate limits for unauthenticated requests
- Script uses public endpoints that should be sufficient
- If needed, add GITHUB_TOKEN to workflow for higher limits

### Debug Mode
Run script manually to see detailed output:
```bash
# Make script executable
chmod +x scripts/update-contributions.sh

# Run with verbose output
./scripts/update-contributions.sh
```

### Check Workflow Logs
1. Go to repository → Actions tab
2. Click on latest workflow run
3. Check logs for any error messages

## 📈 Features

### ✅ Current Features
- ✅ Automatic daily updates
- ✅ Recent activity tracking
- ✅ Repository statistics
- ✅ Network metrics
- ✅ Contribution impact
- ✅ Error handling and backups
- ✅ Manual trigger support

### 🔄 Future Enhancements
- 🎯 Language statistics tracking
- 📊 Star/fork growth tracking
- 🏆 Achievement milestones
- 📈 Contribution streak analysis
- 🌍 Geographic contribution map

## 🔐 Security

- Uses only public GitHub APIs
- No sensitive data stored
- Read-only access to public information
- Backup system prevents data loss
- Secure GitHub Actions environment

## 📞 Support

If you encounter any issues:

1. **Check the logs** in GitHub Actions
2. **Run the test script** to validate setup
3. **Review the documentation** for configuration options
4. **Create an issue** if problems persist

## 🎉 Benefits

- ⚡ **Always up-to-date** profile information
- 🚀 **Professional appearance** with current metrics
- 🔄 **Zero maintenance** - runs automatically  
- 📊 **Comprehensive tracking** of all activity
- 🎯 **Customizable** to your preferences

---

**📝 Note**: This system respects GitHub's API rate limits and only accesses public information. All updates are logged and can be monitored through GitHub Actions.
