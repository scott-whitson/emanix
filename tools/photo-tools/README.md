# Photo Tools

Tools for managing photos across devices and backing up to Google Drive.

## Canonical Photo Location

`~/gdrive/SEW/History/Pictures/` — organized by year (2005/, 2006/, ..., 2026/).

## photo-reconcile

Deduplicates and imports photos into Google Drive Pictures using SHA256 hashing.

```bash
# Index existing gdrive photos (run first, or after manual changes to gdrive)
~/projects/photo-tools/photo-reconcile index

# Preview what would be imported (always dry-run first)
~/projects/photo-tools/photo-reconcile import /path/to/photos --dry-run

# Actually import
~/projects/photo-tools/photo-reconcile import /path/to/photos

# Supports: directories, zip files, directories of zips (Google Takeout)
```

- Hashes every file with SHA256 to detect duplicates
- Sorts into year folders using EXIF > filename > mtime
- Handles Google Takeout JSON sidecars for date extraction
- Index stored in `photo-index.db` (SQLite)

### Verify a photo exists before deleting from phone

```bash
python3 -c "
import sqlite3
db = sqlite3.connect('/home/scott/projects/photo-tools/photo-index.db')
rows = db.execute(\"SELECT path FROM files WHERE path LIKE '%IMG_1527%'\").fetchall()
for r in rows: print(r[0])
"
```

## iPhone Photo Offload Playbook

### What you need

```bash
sudo apt install ifuse libimobiledevice-utils libheif-examples
pipx install icloudpd
```

### Step 1: Pull photos from iCloud (gets everything)

This is the best method. Downloads your entire iCloud photo library directly from Apple's servers.

```bash
# First time — authenticates and downloads
icloudpd -d ~/Pictures/iCloudDownload -u YOUR_APPLE_ID --password-provider console --mfa-provider console

# Subsequent runs — only downloads new photos
icloudpd -d ~/Pictures/iCloudDownload -u YOUR_APPLE_ID
```

- Prompts for password + 2FA code from your phone
- Downloads into date-based folders (YYYY/MM/DD/)
- Resumes where it left off if interrupted
- Hidden photos are NOT included (they stay in iCloud, which is fine)

### Step 2 (optional): Pull directly from iPhone via USB

Only needed if icloudpd doesn't work or you want photos not yet synced to iCloud.

```bash
# Pair and mount
idevicepair pair          # tap "Trust" on iPhone
mkdir -p ~/iphone
ifuse ~/iphone

# Copy photos
mkdir -p ~/Pictures/iPhone
cp ~/iphone/DCIM/*/* ~/Pictures/iPhone/

# Unmount when done
fusermount -u ~/iphone
```

Note: Only photos physically on the device are visible. If "Optimize iPhone Storage"
is enabled, most photos are iCloud-only placeholders. Switch to "Download and Keep
Originals" in Settings > Photos first, wait for downloads, then copy.

### Step 3: Convert HEIC to JPG

```bash
cd ~/Pictures/iPhone   # or wherever
for f in *.HEIC; do
    heif-convert -q 92 "$f" "${f%.HEIC}.jpg" && rm "$f"
done
```

### Step 4: Index and import to Google Drive

```bash
# Index existing photos (takes a while over network mount, ~30k+ files)
~/projects/photo-tools/photo-reconcile index

# Dry-run first to see what's new vs duplicate
~/projects/photo-tools/photo-reconcile import ~/Pictures/iCloudDownload --dry-run
~/projects/photo-tools/photo-reconcile import ~/Pictures/iPhone --dry-run

# Import for real
~/projects/photo-tools/photo-reconcile import ~/Pictures/iCloudDownload
~/projects/photo-tools/photo-reconcile import ~/Pictures/iPhone
```

### Step 5: Verify and delete from phone

Use the database query above to confirm specific photos are in gdrive before deleting
from the phone. Then delete from the iPhone Photos app to free up space.

### Step 6: Clean up staging folders

```bash
rm -rf ~/Pictures/iCloudDownload ~/Pictures/iPhone
```

## Gotchas / Lessons Learned

- **Windows iCloud sync is useless**: iCloud for Windows creates NTFS sparse placeholder
  files (all null bytes) that look like real files but contain no data. Don't trust them.
- **iPhone "Optimize Storage" hides photos from USB**: ifuse can only see photos
  physically downloaded to the device, not iCloud-only thumbnails.
- **icloudpd is the winner**: Downloads everything directly from Apple's servers,
  no phone storage or Windows needed. Just needs Apple ID + 2FA.
- **Hidden album is separate**: Photos marked as Hidden on iPhone don't download
  with icloudpd by default. Use `icloudpd -a Hidden` to get them if needed.
- **HEIC conversion changes hashes**: Converting HEIC to JPG creates files that
  won't dedupe against the HEIC originals. Import originals first if possible.
- **gdrive mount is slow**: Indexing 30k+ files over the network mount takes ~20 min.
  The SQLite index makes subsequent lookups instant.
