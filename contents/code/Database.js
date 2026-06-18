/*
 * KDE Assistant — Database.js
 * SQLite chat history storage helpers
 */

.pragma library

// ──────────────────────────────────────────────
// LocalStorage helpers — chat history
// ──────────────────────────────────────────────

function initDatabase(db) {
    db.transaction(function (tx) {
        tx.executeSql(
            "CREATE TABLE IF NOT EXISTS sessions (" +
            "  id TEXT PRIMARY KEY," +
            "  title TEXT NOT NULL," +
            "  created_at INTEGER NOT NULL," +
            "  updated_at INTEGER NOT NULL" +
            ")"
        );
        tx.executeSql(
            "CREATE TABLE IF NOT EXISTS messages (" +
            "  id TEXT PRIMARY KEY," +
            "  session_id TEXT NOT NULL," +
            "  role TEXT NOT NULL," +
            "  content TEXT NOT NULL," +
            "  timestamp INTEGER NOT NULL," +
            "  FOREIGN KEY(session_id) REFERENCES sessions(id)" +
            ")"
        );
        // ── Memory table (Approach 2) ────────────────────────────
        tx.executeSql(
            "CREATE TABLE IF NOT EXISTS memories (" +
            "  id TEXT PRIMARY KEY," +
            "  content TEXT NOT NULL," +
            "  created_at INTEGER NOT NULL," +
            "  source_session_id TEXT" +
            ")"
        );
    });
}

function loadSessions(db) {
    var sessions = [];
    try {
        db.readTransaction(function (tx) {
            var result = tx.executeSql(
                "SELECT * FROM sessions ORDER BY updated_at DESC LIMIT 50"
            );
            for (var i = 0; i < result.rows.length; i++) {
                sessions.push(result.rows.item(i));
            }
        });
    } catch (e) {
        console.error("loadSessions error:", e);
    }
    return sessions;
}

function loadMessages(db, sessionId) {
    var messages = [];
    try {
        db.readTransaction(function (tx) {
            var result = tx.executeSql(
                "SELECT * FROM messages WHERE session_id = ? ORDER BY timestamp ASC",
                [sessionId]
            );
            for (var i = 0; i < result.rows.length; i++) {
                messages.push(result.rows.item(i));
            }
        });
    } catch (e) {
        console.error("loadMessages error:", e);
    }
    return messages;
}

function createSession(db, id, title) {
    var now = Date.now();
    try {
        db.transaction(function (tx) {
            tx.executeSql(
                "INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)",
                [id, title, now, now]
            );
        });
    } catch (e) {
        console.error("createSession error:", e);
    }
}

function saveMessage(db, sessionId, role, content) {
    var now = Date.now();
    var id = sessionId + "_" + now + "_" + Math.random().toString(36).substr(2, 6);
    try {
        db.transaction(function (tx) {
            tx.executeSql(
                "INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                [id, sessionId, role, content, now]
            );
            tx.executeSql(
                "UPDATE sessions SET updated_at = ? WHERE id = ?",
                [now, sessionId]
            );
        });
    } catch (e) {
        console.error("saveMessage error:", e);
    }
}

function updateSessionTitle(db, sessionId, title) {
    try {
        db.transaction(function (tx) {
            tx.executeSql(
                "UPDATE sessions SET title = ? WHERE id = ?",
                [title, sessionId]
            );
        });
    } catch (e) {
        console.error("updateSessionTitle error:", e);
    }
}

function deleteSession(db, sessionId) {
    try {
        db.transaction(function (tx) {
            tx.executeSql("DELETE FROM messages WHERE session_id = ?", [sessionId]);
            tx.executeSql("DELETE FROM sessions WHERE id = ?", [sessionId]);
        });
    } catch (e) {
        console.error("deleteSession error:", e);
    }
}

// ──────────────────────────────────────────────
// Memory CRUD (Approach 2 — [REMEMBER: ...])
// ──────────────────────────────────────────────

function saveMemory(db, content, sessionId) {
    var now = Date.now();
    var id  = "mem_" + now.toString(36) + "_" + Math.random().toString(36).substr(2, 6);
    try {
        db.transaction(function (tx) {
            tx.executeSql(
                "INSERT INTO memories (id, content, created_at, source_session_id) VALUES (?, ?, ?, ?)",
                [id, content.trim(), now, sessionId || ""]
            );
        });
        return id;
    } catch (e) {
        console.error("saveMemory error:", e);
        return "";
    }
}

function loadMemories(db) {
    var memories = [];
    try {
        db.readTransaction(function (tx) {
            var result = tx.executeSql(
                "SELECT * FROM memories ORDER BY created_at ASC"
            );
            for (var i = 0; i < result.rows.length; i++) {
                memories.push(result.rows.item(i));
            }
        });
    } catch (e) {
        console.error("loadMemories error:", e);
    }
    return memories;
}

function deleteMemory(db, memoryId) {
    try {
        db.transaction(function (tx) {
            tx.executeSql("DELETE FROM memories WHERE id = ?", [memoryId]);
        });
    } catch (e) {
        console.error("deleteMemory error:", e);
    }
}

function clearMemories(db) {
    try {
        db.transaction(function (tx) {
            tx.executeSql("DELETE FROM memories");
        });
    } catch (e) {
        console.error("clearMemories error:", e);
    }
}
