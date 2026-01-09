# 🔐 GitHub Token Setup for Private Contributions

To show **private contributions** in your README, you need to set up a GitHub Personal Access Token (PAT).

## 📋 Steps to Create GitHub Token

### 1. Generate a Personal Access Token

1. Go to **GitHub Settings**: https://github.com/settings/tokens
2. Click **"Generate new token (classic)"** or use fine-grained tokens
3. Give it a descriptive name: `README Auto-Update Token`
4. Set expiration (recommended: 90 days or No expiration)
5. Select the following scopes:
   - ✅ `repo` (Full control of private repositories)
   - ✅ `read:user` (Read user profile data)
   - ✅ `read:org` (Read organization data - optional)

6. Click **"Generate token"**
7. **⚠️ IMPORTANT**: Copy the token immediately (you won't see it again!)

### 2. Add Token to GitHub Actions

#### Option A: Repository Secret (Recommended)

1. Go to your repository settings
2. Navigate to **Settings → Secrets and variables → Actions**
3. Click **"New repository secret"**
4. Name: `GH_TOKEN` or `PERSONAL_ACCESS_TOKEN`
5. Value: Paste your GitHub token
6. Click **"Add secret"**

#### Option B: Local Testing

For local testing, export the token as an environment variable:

```bash
export GITHUB_TOKEN="ghp_your_token_here"
./scripts/update-contributions.sh
```

### 3. Update GitHub Actions Workflow

Edit `.github/workflows/update-readme.yml` to use the token:

```yaml
- name: 🚀 Run Contribution Update Script
  env:
    GITHUB_TOKEN: ${{ secrets.GH_TOKEN }}  # Use your secret name
  run: |
    chmod +x scripts/update-contributions.sh
    ./scripts/update-contributions.sh
```

## ✨ What You'll Get with Token

### Without Token (Public Only)
- ✅ Public repositories
- ✅ Public commits
- ✅ Public PRs and issues
- ❌ Private repositories (hidden)
- ❌ Private contributions (not counted)

### With Token (Public + Private)
- ✅ Public repositories
- ✅ Public commits
- ✅ Public PRs and issues
- ✅ **Private repositories count** (🔒 badge shown)
- ✅ **Private commits** (marked with 🔒)
- ✅ **Total accurate contribution count**

## 🔒 Security Notes

1. **Never commit tokens** to your repository
2. **Use repository secrets** for GitHub Actions
3. **Rotate tokens regularly** (every 90 days recommended)
4. **Use minimal scopes** required for the task
5. **Revoke tokens** if compromised

## 🧪 Testing

Test if your token works:

```bash
# Set the token
export GITHUB_TOKEN="your_token_here"

# Run the script
./scripts/update-contributions.sh

# You should see:
# "Using authenticated API (includes private repos)"
# "Stats: X public repos, Y private repos, ..."
```

## 🚀 Example Output with Private Repos

```
📈 Contribution Impact
┌──────────────────────┬──────────────────────┬──────────────────────┬──────────────────────┐
│  🔥 Total Commits    │  📝 Public Repos     │  🔒 Private Repos    │  🎯 Network          │
│       15             │       139            │        5             │    82/11             │
│   Last 7 Days        │     Public           │      Private         │ Following/Followers  │
└──────────────────────┴──────────────────────┴──────────────────────┴──────────────────────┘
```

Recent contributions will show 🔒 for private repositories.

## ❓ Troubleshooting

### Token not working?
- Check if token has correct scopes (`repo`, `read:user`)
- Verify token hasn't expired
- Make sure secret name matches in workflow file

### Still showing only public?
- Check workflow logs for authentication message
- Ensure `GITHUB_TOKEN` environment variable is set
- Verify the token is passed correctly to the script

### Private repos not showing?
- Confirm repositories are actually private
- Check if you have access to those repositories
- Token must have `repo` scope (not just `public_repo`)

---

**Need Help?** Check the [GitHub Docs on Personal Access Tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token)
