# Restore Feature Testing Guide

## Feature Summary

Advanced disk space monitoring and intelligent storage location selection for file downloads.

### Components Implemented

#### Backend (PHP)

1. **Storage Space API** (`GET /clients/{id}/storage-space`)
   - Returns disk space info for a given storage location
   - Query params: `?location_id={id}` (optional)
   - Returns: free_bytes, total_bytes, percent_free, location label

2. **Size Estimation API** (`GET /clients/{id}/archive/{archive_id}/estimate-size`)
   - Calculates uncompressed size of selected files from ClickHouse
   - Query params: `?files[]={path1}&files[]={path2}`
   - Returns: uncompressed_bytes, estimated_bytes (with 1.5x overhead)

3. **Enhanced Download Controller**
   - Accepts `storage_location_id` in POST parameters
   - Validates location (must be local type, readable, writable)
   - Uses selected location instead of hardcoded `/var/bbs/home`
   - Checks disk space BEFORE extraction (150% of archive original_size)
   - Returns clear error messages if space insufficient

#### Frontend (UI)

1. **Storage Location Selector**
   - Dropdown in download panel
   - Shows available local storage locations
   - Updates hidden form field `storage_location_id`

2. **Real-time Space Indicator**
   - Shows storage location label
   - Displays free space in GB
   - Progress bar with color coding:
     - Green: >20% free
     - Yellow: 10-20% free  
     - Red: <10% free

3. **Download Size Estimator**
   - Shows estimated download size
   - For individual files: calculated from file_catalog via ClickHouse
   - For entire archive: read from `data-size` attribute
   - Includes 1.5x uncompressed overhead
   - Updates dynamically as file selection changes

4. **Space Warning**
   - Appears when required space > available free space
   - Disables download button with tooltip "Insufficient disk space"
   - Auto-resolves when space becomes available

#### JavaScript (restore.js)

1. **updateStorageSpaceInfo()**
   - Called on storage location change
   - Fetches space data from API
   - Updates progress bar and location label
   - Triggers size re-estimation

2. **updateDownloadSizeEstimate()**
   - Called on archive selection and file selection
   - For entire archive: reads data-size attribute
   - For selected files: fetches from size estimation API
   - Calls checkSpaceWarning()

3. **checkSpaceWarning(requiredBytes)**
   - Compares required bytes against available space
   - Disables/enables download button
   - Shows/hides warning message

## Test Scenarios

### Scenario 1: Basic Size Estimation
**Setup:** Archive with known files selected

**Steps:**
1. Select an archive from dropdown
2. Browse and select individual files
3. Observe "Estimated size" display

**Expected Results:**
- Size estimated and displayed
- Format: "X.XX MB (est.)"
- Value estimates compression (1.5x uncompressed)

---

### Scenario 2: Entire Archive Download
**Setup:** Archive available

**Steps:**
1. Select an archive from dropdown
2. Click "Download entire archive" checkbox
3. Observe size display

**Expected Results:**
- Size shows archive's original_size (uncompressed)
- No "(est.)" label (exact size)
- Matches archive original_size from database

---

### Scenario 3: Storage Location Selection
**Setup:** Multiple local storage locations configured

**Steps:**
1. Select a storage location from dropdown
2. Observe space indicator update
3. Change to different location
4. Observe space indicator update

**Expected Results:**
- Label updates to show location name
- Free space updates to reflect that location
- Progress bar shows current utilization
- Color changes based on free percentage

---

### Scenario 4: Space Warning
**Setup:** Storage location with limited free space

**Steps:**
1. Select storage location with <X free space
2. Select files requiring >X space
3. Observe download button

**Expected Results:**
- Warning div appears
- Download button becomes disabled
- Button shows tooltip: "Insufficient disk space"

---

### Scenario 5: Space Becomes Available
**Setup:** Space warning active

**Steps:**
1. Free up space on storage location (e.g., delete files)
2. Change storage location selector (triggers re-check)
3. Observe warning

**Expected Results:**
- Warning disappears
- Download button becomes enabled
- Button tooltip cleared

---

### Scenario 6: Download with Custom Location
**Setup:** File(s) selected, custom storage location chosen

**Steps:**
1. Select files to download
2. Choose custom storage location from dropdown
3. Click "Download"
4. Monitor server response

**Expected Results:**
- Download succeeds
- Files extracted to selected storage location path
- No "Insufficient disk space" error
- Metadata shows custom location_id was used

---

### Scenario 7: Download Fails - Insufficient Space
**Setup:** Files requiring 5GB selected, location has only 2GB free

**Steps:**
1. Select the files
2. Observe warning appears
3. Try to download (button should be disabled)
4. If button somehow enabled, observe server response

**Expected Results:**
- Warning appears immediately
- Download button disabled
- Server would return: "Not enough disk space... Required: 5000 MB"

---

### Scenario 8: Archive Dropdown data-size Validation
**Setup:** Any archive list loaded

**Steps:**
1. Open browser DevTools (F12)
2. In Console, run:
   ```javascript
   Array.from(document.querySelectorAll('#archive-select option'))
     .filter(o => o.value)
     .forEach(o => console.log(`Archive #${o.value}: ${o.dataset.size} bytes`))
   ```

**Expected Results:**
- All archive options show data-size attributes
- Values are positive integers (bytes)
- Matches archive.original_size from database

---

## Database Validation

### Verify Archive Sizes
```sql
SELECT id, archive_name, original_size, created_at 
FROM archives 
ORDER BY created_at DESC 
LIMIT 10;
```

**Expected Results:** original_size should be >0 for all archives with data

### Verify Storage Locations
```sql
SELECT id, label, type, path FROM storage_locations 
WHERE type = 'local' AND active = 1;
```

**Expected Results:** At least one local storage location exists

### Verify ClickHouse File Catalog
```sql
SELECT COUNT(*) as file_count, SUM(file_size) as total_bytes
FROM file_catalog 
WHERE agent_id = ? AND archive_id = ?;
```

**Expected Results:** Files exist and total_bytes > 0 for tested archives

---

## API Endpoint Testing

### Test Storage Space Endpoint
```bash
curl -H "Cookie: PHPSESSID=..." \
  "https://example.com/clients/123/storage-space?location_id=5"
```

**Expected Response:**
```json
{
  "location": "Storage Location Label",
  "free_bytes": 1073741824,
  "total_bytes": 2147483648,
  "percent_free": 50.0,
  "free_gb": 1.0
}
```

### Test Size Estimation Endpoint
```bash
curl -H "Cookie: PHPSESSID=..." \
  "https://example.com/clients/123/archive/456/estimate-size?files[]=/path/to/file&files[]=/path/to/dir"
```

**Expected Response:**
```json
{
  "uncompressed_bytes": 536870912,
  "uncompressed_mb": 512.0,
  "estimated_bytes": 805306368,
  "estimated_mb": 768.0
}
```

---

## Browser Console Testing

### Verify Global Variables
```javascript
// Should exist
agentId
archiveSelect
storageSelect
downloadBtn
selectedPaths
entireArchiveSelected
```

### Verify Functions
```javascript
// Should be callable
updateStorageSpaceInfo()
updateDownloadSizeEstimate()
checkSpaceWarning(1024*1024*100)  // 100MB
formatSize(1024*1024*1024)  // Should return "1.0 GB"
```

### Monitor Fetch Calls
```javascript
// Enable network tab in DevTools
// Select an archive: should call /storage-space
// Select files: should call /archive/{id}/estimate-size
// Change location: should call /storage-space
```

---

## Regression Testing

### Ensure Existing Features Still Work

1. **Database Restore Mode**
   - Select database backup
   - List databases
   - Download works

2. **File Browse Mode**
   - Browse archive files
   - Search files (if ClickHouse available)
   - Restore individual files

3. **Server-side Restore**
   - Create restore job
   - Monitor job progress
   - Verify restored files

4. **Different Storage Types**
   - Remote SSH repositories
   - S3 repositories
   - (Note: downloads still use local temp, but repo access should work)

---

## Known Limitations

1. **Download temporary storage**: Always uses local filesystem (cannot extract to S3/SSH directly)
   - Size validation uses the chosen storage location's free space
   - If no location selected, falls back to system temp

2. **ClickHouse dependency**: Size estimation requires ClickHouse for file listings
   - Falls back gracefully if unavailable
   - Entire archive download still works (uses data-size attribute)

3. **Archive original_size accuracy**: Depends on Borg's accurate reporting
   - May include metadata overhead
   - Estimate uses 1.5x multiplier for safety

4. **Concurrent downloads**: Multiple downloads to same location may cause space issues
   - Warning only checks at time of button click
   - Server validates again before extraction

---

## Success Criteria

✅ All test scenarios pass without errors
✅ Size estimates are accurate (within 10% of actual)
✅ Space warnings appear/disappear correctly
✅ Download button disabled when space insufficient
✅ Selected storage location used in download
✅ Error messages are clear and actionable
✅ No regression in existing restore features
✅ JavaScript console has no errors
✅ Network requests complete successfully
