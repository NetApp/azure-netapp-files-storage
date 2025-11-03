# Private Fork Setup Guide

This guide helps you set up a private fork to work on changes before pushing to the public repository.

## Step 1: Create Private Fork on GitHub

1. **Go to the public repository:**
   ```
   https://github.com/NetApp/azure-netapp-files-storage
   ```

2. **Click the "Fork" button** (top right corner)

3. **Fork the repository:**
   - Select your GitHub account/organization
   - Optionally check "Copy the main branch only"
   - Click "Create fork"

4. **Make the fork private:**
   - Go to your forked repository
   - Click **Settings** (top right)
   - Scroll down to **"Danger Zone"**
   - Click **"Change visibility"**
   - Select **"Make private"**
   - Confirm by typing your repository name

5. **Copy the private fork URL:**
   - It will look like: `https://github.com/YOUR-USERNAME/azure-netapp-files-storage.git`

## Step 2: Add Private Fork as Remote

In your local repository, add the private fork as a remote:

```bash
cd /Users/prabu/projects/azure-netapp-files-storage-main

# Add private fork as remote
git remote add private https://github.com/YOUR-USERNAME/azure-netapp-files-storage.git

# Verify remotes
git remote -v
```

You should now see:
- `origin` - points to public repo
- `private` - points to your private fork

## Step 3: Commit Your Changes

```bash
# Stage all changes
git add .

# Commit with descriptive message
git commit -m "Add PostgreSQL VM + ANF templates

- Add Terraform template for PostgreSQL on VM with ANF
- Add ARM template for PostgreSQL on VM with ANF
- Add PowerShell script for PostgreSQL on VM with ANF
- Remove PostgreSQL Flexible Server templates
- Update README with PostgreSQL VM + ANF option
- Add comprehensive testing guide"
```

## Step 4: Push to Private Fork

```bash
# Push to private fork (keeps changes private)
git push private main

# Or if it's your first push
git push -u private main
```

## Step 5: Test and Iterate

Your changes are now in your private fork. You can:
- Test deployments
- Make additional commits
- Push to private fork: `git push private main`
- Keep changes private until ready

## Step 6: Sync to Public Repository (When Ready)

When you're ready to make changes public:

```bash
# Push to public repository
git push origin main

# Or open a Pull Request on GitHub
# 1. Go to https://github.com/NetApp/azure-netapp-files-storage
# 2. Click "Pull requests" → "New pull request"
# 3. Compare across forks
# 4. Select your private fork as source
```

## Working with Both Remotes

### Push to private fork (default):
```bash
git push private main
```

### Push to public repo:
```bash
git push origin main
```

### Push to both:
```bash
git push private main && git push origin main
```

### Pull from public repo:
```bash
git pull origin main
```

### Sync private fork from public:
```bash
git pull origin main
git push private main
```

## Benefits of This Approach

✅ **Privacy**: Changes stay private in your fork  
✅ **Testing**: Test deployments without affecting public repo  
✅ **Iteration**: Make multiple commits before going public  
✅ **Control**: Decide when to make changes public  
✅ **Backup**: Private fork serves as backup of your work  

## Troubleshooting

### If you get "remote already exists":
```bash
# Remove existing remote
git remote remove private

# Add again with correct URL
git remote add private <your-private-fork-url>
```

### If you need to update remote URL:
```bash
git remote set-url private <new-url>
```

### To see all remotes:
```bash
git remote -v
```

