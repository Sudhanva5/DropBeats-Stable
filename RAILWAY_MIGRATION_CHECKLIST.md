# Railway Migration Checklist

Complete guide for migrating DropBeat backend from Render to Railway.

## ✅ Files Created

I've created the following files for Railway deployment:

1. **`Server/railway.json`** - Railway deployment configuration
2. **`Server/nixpacks.toml`** - Nixpacks build configuration (installs yt-dlp)
3. **`Server/RAILWAY_DEPLOYMENT.md`** - Detailed deployment guide
4. **`DropBeat/DropBeat/Config/BackendConfig.swift`** - Centralized backend URL configuration

## 📋 Migration Steps

### Phase 1: Deploy Backend to Railway (Server Repository)

1. **Navigate to Server directory**
   ```bash
   cd Server
   ```

2. **Commit Railway configuration files**
   ```bash
   git status  # Check what's new
   git add railway.json nixpacks.toml RAILWAY_DEPLOYMENT.md
   git commit -m "Add Railway deployment configuration"
   git push origin main
   ```

3. **Deploy to Railway**
   - Go to https://railway.app
   - Click "New Project"
   - Select "Deploy from GitHub repo"
   - Choose `DropBeats-Server` repository
   - Railway will auto-deploy using the configuration

4. **Get Railway URL**
   - Once deployed, Railway assigns a URL like: `https://dropbeat-api-production.up.railway.app`
   - **Copy this URL** - you'll need it in Phase 2

5. **Test Railway Deployment**
   ```bash
   # Replace with your actual Railway URL
   RAILWAY_URL="https://your-railway-url.up.railway.app"

   # Health check
   curl $RAILWAY_URL/health

   # Test search
   curl "$RAILWAY_URL/search/test"

   # Test stream URL (should return a playable URL)
   curl "$RAILWAY_URL/stream-url/dQw4w9WgXcQ"
   ```

### Phase 2: Update macOS App (Main Repository)

1. **Add BackendConfig to Xcode**
   - Open `DropBeat.xcodeproj` in Xcode
   - Right-click on `DropBeat/Config` folder
   - Select "Add Files to DropBeat"
   - Navigate to `DropBeat/DropBeat/Config/BackendConfig.swift`
   - Ensure "Copy items if needed" is checked
   - Click "Add"

2. **Update Railway URL in BackendConfig**
   - Open `DropBeat/DropBeat/Config/BackendConfig.swift`
   - Find line ~23: `return "https://your-railway-url.up.railway.app"`
   - Replace with your actual Railway URL
   - Example: `return "https://dropbeat-api-production.up.railway.app"`

3. **Update Service Files** (I'll do this next)
   - Replace hardcoded `http://localhost:8000` with `BackendConfig.baseURL`
   - Files to update:
     - `SearchService.swift`
     - `YTDLPService.swift`
     - `RecommendationService.swift`
     - `SongInfoService.swift`

4. **Test Locally First**
   - Build and run the app in DEBUG mode (uses localhost)
   - Start your local backend server
   - Verify search, playback, and recommendations work

5. **Test with Railway**
   - Build in RELEASE mode (uses Railway URL)
   - Verify all features work with Railway backend
   - No local backend server should be needed

6. **Commit Changes**
   ```bash
   git add DropBeat/DropBeat/Config/BackendConfig.swift
   git add DropBeat/DropBeat/Services/*.swift
   git commit -m "Add Railway backend support with environment switching"
   git push origin yt-dlp
   ```

### Phase 3: Distribute Updated App

1. **Build Production App**
   ```bash
   cd scripts
   ./build_dmg.sh  # Or your build script
   ```

2. **Test DMG**
   - Install the DMG on a clean macOS system
   - Verify it connects to Railway (not localhost)
   - Test all features

3. **Upload to Gumroad**
   - Upload new DMG with Railway backend
   - Update version number
   - Add release notes mentioning cloud backend

## 🎯 Current vs New Architecture

### Before (Render/Localhost):
```
macOS App → http://localhost:8000 (local backend)
```

### After (Railway):
```
macOS App (DEBUG) → http://localhost:8000 (local development)
macOS App (RELEASE) → https://your-railway-url.up.railway.app (production)
```

## 📊 Benefits of Railway

1. **Automatic Deployment** - Push to GitHub → Auto-deploy to Railway
2. **Better Uptime** - Railway has better reliability than Render free tier
3. **Faster Cold Starts** - Railway instances wake up faster
4. **Better Logs** - Real-time logging and monitoring
5. **No Sleep** - On paid plans, no cold starts

## ⚠️ Important Notes

1. **No Authentication Required** - Backend works in unauthenticated mode
2. **yt-dlp is Critical** - Ensure `nixpacks.toml` installs it correctly
3. **CORS Configuration** - Railway allows all origins (`*`) for macOS app
4. **Environment Detection** - DEBUG builds use localhost, RELEASE uses Railway

## 🔧 Troubleshooting

### App connects to localhost in RELEASE build
- Check `BackendConfig.swift` environment detection
- Verify you're building in RELEASE mode
- Print `BackendConfig.baseURL` to console

### Railway deployment fails
- Check Railway logs for errors
- Verify `nixpacks.toml` syntax
- Ensure yt-dlp installs successfully

### CORS errors
- Check Railway environment variables
- Verify `ALLOWED_ORIGINS` is set to `*`

## 💰 Cost Comparison

**Render Free Tier:**
- ❌ Sleeps after 15 minutes of inactivity
- ❌ Slow cold starts (30-60 seconds)
- ❌ Limited to 750 hours/month

**Railway:**
- ✅ $5 free credit/month
- ✅ Fast cold starts (<5 seconds)
- ✅ Better monitoring and logs
- ✅ Estimated $2-5/month for light usage

## 📝 Next Steps

1. ⬜ Deploy backend to Railway (Phase 1)
2. ⬜ Update macOS app configuration (Phase 2)
3. ⬜ Test both DEBUG and RELEASE builds
4. ⬜ Distribute updated app (Phase 3)
5. ⬜ Monitor Railway usage and costs
6. ⬜ Shut down Render deployment
