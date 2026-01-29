# Borg Backup Server — API Reference

The BBS agent API is used by the Python agent running on endpoints. All endpoints are authenticated via Bearer token (the agent's API key).

**Base URL:** `https://your-server.com`

---

## Authentication

All requests must include the API key in the `Authorization` header:

```
Authorization: Bearer <64-character-hex-api-key>
```

Every authenticated request updates the agent's `last_heartbeat` and `status` to `online`.

**Rate limiting:** 20 failed authentication attempts per 5 minutes per IP. Returns `429 Too Many Requests` when exceeded.

---

## Endpoints

### POST /api/agent/register

One-time registration. Called when the agent starts for the first time.

**Request body (JSON):**

```json
{
    "hostname": "web-prod-01",
    "ip_address": "192.168.1.100",
    "os_info": "Ubuntu 22.04.3 LTS",
    "borg_version": "1.2.6",
    "agent_version": "1.0.0"
}
```

**Response (200):**

```json
{
    "status": "ok",
    "agent_id": 1,
    "name": "web-prod-01",
    "poll_interval": 30
}
```

The `poll_interval` is the server-configured interval (in seconds) that the agent should use between task polls.

---

### GET /api/agent/tasks

Poll for pending tasks. The agent calls this on every poll cycle.

**Request body:** None

**Response (200) — no tasks:**

```json
{
    "status": "ok",
    "tasks": []
}
```

**Response (200) — with tasks:**

```json
{
    "status": "ok",
    "tasks": [
        {
            "task": "backup",
            "command": ["borg", "create", "--log-json", "--list", "--progress", "--compression", "lz4", "--noatime", "--exclude", "*.tmp", "/mnt/backups/repo::backup-2026-01-28_14-30-00", "/home", "/etc"],
            "env": {
                "BORG_PASSPHRASE": "decrypted-passphrase",
                "BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK": "yes"
            },
            "job_id": 42,
            "archive_name": "backup-2026-01-28_14-30-00",
            "directories": "/home\n/etc"
        }
    ]
}
```

**Task types:**

| Type | Description |
|---|---|
| `backup` | Run `borg create` |
| `prune` | Run `borg prune` |
| `restore` | Run `borg extract` |

The `command` array contains the full borg command to execute. The `env` object contains environment variables to set (primarily `BORG_PASSPHRASE`).

---

### POST /api/agent/progress

Report progress during task execution. Called every ~5 seconds while a backup is running.

**Request body (JSON):**

```json
{
    "job_id": 42,
    "files_total": 8601,
    "files_processed": 3200,
    "bytes_total": 1073741824,
    "bytes_processed": 402653184
}
```

**Response (200):**

```json
{
    "status": "ok"
}
```

On the first progress call for a job, `started_at` is set and status changes to `running`.

---

### POST /api/agent/status

Report task completion or failure. Called once when a task finishes.

**Request body (JSON) — success:**

```json
{
    "job_id": 42,
    "result": "completed",
    "files_total": 8601,
    "files_processed": 8601,
    "bytes_total": 1073741824,
    "bytes_processed": 1073741824,
    "archive_name": "backup-2026-01-28_14-30-00",
    "original_size": 1073741824,
    "deduplicated_size": 52428800
}
```

**Request body (JSON) — failure:**

```json
{
    "job_id": 42,
    "result": "failed",
    "files_total": 8601,
    "files_processed": 3200,
    "error_log": "borg: error: repository does not exist"
}
```

**Response (200):**

```json
{
    "status": "ok",
    "archive_id": 7
}
```

On success:
- An archive record is created in the database
- Repository size and archive count are updated
- `archive_id` is returned (used for catalog upload)

On failure:
- Error log is stored on the job record
- Email notification is sent to all admin users (if SMTP is configured)

**Borg exit codes:** Exit code 0 or 1 (warnings) are treated as success. Exit code 2+ is treated as failure.

---

### POST /api/agent/heartbeat

Simple health check. Useful if the agent has been idle (no tasks) and wants to confirm connectivity.

**Request body:** None (or empty JSON `{}`)

**Response (200):**

```json
{
    "status": "ok",
    "agent_id": 1,
    "server_time": "2026-01-28 14:35:00"
}
```

Note: Every authenticated API call already updates the heartbeat, so this endpoint is only needed for explicit keep-alive during long idle periods.

---

### POST /api/agent/info

Report updated system information. Called periodically or when system info changes.

**Request body (JSON):**

```json
{
    "hostname": "web-prod-01",
    "ip_address": "192.168.1.100",
    "os_info": "Ubuntu 22.04.4 LTS",
    "borg_version": "1.2.7",
    "agent_version": "1.1.0"
}
```

**Response (200):**

```json
{
    "status": "ok"
}
```

All fields are optional — only provided fields are updated.

---

### POST /api/agent/catalog

Upload file catalog entries after a successful backup. The agent sends file entries in batches (typically 1000 per request).

**Request body (JSON):**

```json
{
    "archive_id": 7,
    "files": [
        {
            "path": "/home/user/document.txt",
            "size": 4096,
            "status": "A",
            "mtime": "2026-01-28 10:00:00"
        },
        {
            "path": "/etc/nginx/nginx.conf",
            "size": 2048,
            "status": "M",
            "mtime": "2026-01-27 08:30:00"
        }
    ]
}
```

**File status values:**

| Status | Meaning |
|---|---|
| `A` | Added (new file) |
| `M` | Modified (changed since last archive) |
| `U` | Unchanged |
| `E` | Error (could not read) |

**Response (200):**

```json
{
    "status": "ok",
    "inserted": 2
}
```

The server extracts `file_name` (basename) from `path` on insert for search indexing.

---

## Error Responses

All endpoints return consistent error responses:

**401 Unauthorized** — Invalid or missing API key:

```json
{
    "error": "Unauthorized"
}
```

**429 Too Many Requests** — Rate limit exceeded:

```json
{
    "error": "Rate limit exceeded. Try again later."
}
```

**404 Not Found** — Invalid endpoint.

**500 Internal Server Error** — Server-side error (check server logs).

---

## Internal Web API Endpoints

These endpoints are used by the BBS web UI (authenticated via session, not API key).

### GET /dashboard/json

Returns dashboard data for AJAX refresh.

**Response:** JSON with stat cards, chart data, active jobs, recent jobs, server log, server stats.

### GET /clients/{id}/catalog/{archive_id}

Paginated file catalog for an archive.

**Query params:**
- `page` — Page number (default 1, 100 per page)
- `search` — Filter by file name or path (LIKE match)

**Response:**

```json
{
    "files": [
        {"id": 1, "file_path": "/etc/hosts", "file_name": "hosts", "file_size": 256, "status": "U", "mtime": "2026-01-28 10:00:00"}
    ],
    "total": 1,
    "page": 1,
    "pages": 1
}
```

### GET /clients/{id}/catalog/{archive_id}/tree

Lazy-loading directory tree for an archive.

**Query params:**
- `path` — Directory prefix to list children of (default `/`)

**Response:**

```json
{
    "dirs": [
        {"name": "etc", "path": "/etc/", "file_count": 150, "total_size": 524288}
    ],
    "files": [
        {"id": 5, "file_path": "/README.md", "file_name": "README.md", "file_size": 1024, "status": "A"}
    ],
    "path": "/"
}
```

### GET /api/templates/{id}

Returns a backup template as JSON (for form pre-fill).

**Response:**

```json
{
    "id": 1,
    "name": "Web Server",
    "description": "Web server configs and sites",
    "directories": "/var/www\n/etc/nginx\n/etc/apache2\n/etc/letsencrypt",
    "excludes": "*.tmp\n*.log\ncache/"
}
```
