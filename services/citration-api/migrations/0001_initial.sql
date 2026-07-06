CREATE TABLE users (
  id TEXT PRIMARY KEY,
  email TEXT,
  apple_user_id TEXT UNIQUE,
  display_name TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE libraries (
  id TEXT PRIMARY KEY,
  slug TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  created_by_user_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (created_by_user_id) REFERENCES users(id)
);

CREATE TABLE library_members (
  library_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('owner', 'editor', 'viewer')),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (library_id, user_id),
  FOREIGN KEY (library_id) REFERENCES libraries(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  display_name TEXT,
  platform TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_seen_at TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE library_state (
  library_id TEXT PRIMARY KEY,
  current_version INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (library_id) REFERENCES libraries(id) ON DELETE CASCADE
);

CREATE TABLE sync_objects (
  library_id TEXT NOT NULL,
  object_type TEXT NOT NULL,
  object_id TEXT NOT NULL,
  version INTEGER NOT NULL,
  body_json TEXT,
  body_hash TEXT,
  deleted_at TEXT,
  updated_by_device_id TEXT,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (library_id, object_type, object_id),
  FOREIGN KEY (library_id) REFERENCES libraries(id) ON DELETE CASCADE,
  FOREIGN KEY (updated_by_device_id) REFERENCES devices(id) ON DELETE SET NULL
);

CREATE INDEX sync_objects_library_version
  ON sync_objects (library_id, version);

CREATE INDEX sync_objects_type
  ON sync_objects (library_id, object_type, version);

CREATE TABLE sync_events (
  library_id TEXT NOT NULL,
  version INTEGER NOT NULL,
  object_type TEXT NOT NULL,
  object_id TEXT NOT NULL,
  op TEXT NOT NULL CHECK (op IN ('upsert', 'delete')),
  body_json TEXT,
  body_hash TEXT,
  deleted_at TEXT,
  updated_by_device_id TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (library_id, version, object_type, object_id),
  FOREIGN KEY (library_id) REFERENCES libraries(id) ON DELETE CASCADE,
  FOREIGN KEY (updated_by_device_id) REFERENCES devices(id) ON DELETE SET NULL
);

CREATE TABLE attachments (
  library_id TEXT NOT NULL,
  attachment_id TEXT NOT NULL,
  item_id TEXT NOT NULL,
  filename TEXT NOT NULL,
  content_type TEXT NOT NULL,
  byte_size INTEGER NOT NULL,
  checksum_sha256 TEXT,
  r2_key TEXT NOT NULL UNIQUE,
  upload_state TEXT NOT NULL CHECK (upload_state IN ('reserved', 'uploaded', 'failed', 'deleted')),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (library_id, attachment_id),
  FOREIGN KEY (library_id) REFERENCES libraries(id) ON DELETE CASCADE
);

CREATE INDEX attachments_item
  ON attachments (library_id, item_id);

CREATE TABLE idempotency_keys (
  library_id TEXT NOT NULL,
  key TEXT NOT NULL,
  request_hash TEXT NOT NULL,
  response_json TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at TEXT NOT NULL,
  PRIMARY KEY (library_id, key),
  FOREIGN KEY (library_id) REFERENCES libraries(id) ON DELETE CASCADE
);
