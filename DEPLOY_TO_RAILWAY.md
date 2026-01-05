# Deploy DropBeat Backend to Railway

Simple 3-step deployment guide.

## ✅ What's Ready

All configuration files are already created:
- **Server/railway.json** - Railway deployment config
- **Server/nixpacks.toml** - Installs Python + yt-dlp
- **DropBeat/Config/BackendConfig.swift** - Backend URL configuration
- All services updated to use BackendConfig

## 🚀 Deployment Steps

### Step 1: Deploy Backend to Railway

#### Option A: Deploy via Web (Easiest)

1. Go to https://railway.app and sign in
2. Click **"New Project"**
3. Select **"Deploy from GitHub repo"**
4. Choose **`DropBeats-Server`** repository
5. Railway will automatically:
   - Detect `nixpacks.toml` configuration
   - Install Python 3.11 and yt-dlp
   - Install Python dependencies
   - Start the server
6. Once deployed, copy your Railway URL (looks like `https://dropbeat-api-production.up.railway.app`)

#### Option B: Deploy via CLI

```bash
# Install Railway CLI
npm install -g @railway/cli

# Login to Railway
railway login

# Navigate to Server directory
cd Server

# Initialize and deploy
railway init
railway up

# Get your deployment URL
railway domain
```

### Step 2: Update macOS App with Railway URL

1. **Open BackendConfig.swift**
   - File: `DropBeat/DropBeat/Config/BackendConfig.swift`
   - Find line 9: `static let baseURL = "https://your-railway-url.up.railway.app"`

2. **Replace with your actual Railway URL**
   ```swift
   static let baseURL = "https://dropbeat-api-production.up.railway.app"
   ```

3. **Save the file**

### Step 3: Build and Distribute

1. **Test the app**
   - Build and run in Xcode
   - Search for a song
   - Verify playback works

2. **Build for distribution**
   ```bash
   cd scripts
   ./build_dmg.sh
   ```

3. **Upload to Gumroad**
   - Upload the new DMG
   - Update version notes

## ✅ Verify Deployment

Test your Railway backend:

```bash
# Replace with your actual Railway URL
RAILWAY_URL="https://your-railway-url.up.railway.app"

# Health check (should return {"status": "healthy"})
curl $RAILWAY_URL/health

# Test search (should return song results)
curl "$RAILWAY_URL/search/test"

# Test stream URL (should return a playable stream URL)
curl "$RAILWAY_URL/stream-url/dQw4w9WgXcQ"
```

## 📊 No Environment Variables Needed

The backend works in **unauthenticated mode** - no YouTube Music OAuth required!

Railway automatically sets:
- `PORT` - Auto-assigned by Railway
- `ALLOWED_ORIGINS` - Defaults to `*` (allows macOS app)

## 💰 Railway Costs

**Free Tier:**
- $5 credit per month
- ~500 hours of runtime

**Estimated Usage:**
- Small user base: ~$2-3/month
- Medium (500 users): ~$8-12/month

## 🔍 Monitoring

Railway dashboard shows:
- **Logs** - Real-time application logs
- **Metrics** - CPU, memory, network
- **Deployments** - Deployment history and rollbacks

## 🚨 Troubleshooting

### "Module 'yt-dlp' not found"
- Check Railway deployment logs
- Verify `nixpacks.toml` has `yt-dlp` in nixPkgs

### App can't connect to backend
- Verify BackendConfig.baseURL matches Railway URL
- Check Railway deployment is running (not paused)
- Test Railway URL with curl commands above

### Search returns no results
- Backend works in unauthenticated mode
- Check Railway logs for ytmusicapi errors
- Verify Railway deployment health

## 📝 Summary

1. ✅ Deploy Server repo to Railway → Get URL
2. ✅ Update BackendConfig.swift with Railway URL
3. ✅ Build and distribute app

That's it! Your backend is now on Railway. 🎉
