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
        // ── Task groups ──────────────────────────────────────────
        tx.executeSql(
            "CREATE TABLE IF NOT EXISTS task_groups (" +
            "  id TEXT PRIMARY KEY," +
            "  name TEXT NOT NULL," +
            "  color TEXT DEFAULT ''," +
            "  sort_order INTEGER DEFAULT 0," +
            "  created_at INTEGER NOT NULL" +
            ")"
        );
        // ── Tasks ────────────────────────────────────────────────
        tx.executeSql(
            "CREATE TABLE IF NOT EXISTS tasks (" +
            "  id TEXT PRIMARY KEY," +
            "  group_id TEXT DEFAULT ''," +
            "  title TEXT NOT NULL," +
            "  description TEXT DEFAULT ''," +
            "  status TEXT DEFAULT 'pending'," +
            "  priority INTEGER DEFAULT 0," +
            "  due_date INTEGER," +
            "  recurrence TEXT DEFAULT ''," +
            "  created_at INTEGER NOT NULL," +
            "  completed_at INTEGER," +
            "  source_session_id TEXT" +
            ")"
        );
        // ── Subtasks ─────────────────────────────────────────────
        tx.executeSql(
            "CREATE TABLE IF NOT EXISTS subtasks (" +
            "  id TEXT PRIMARY KEY," +
            "  task_id TEXT NOT NULL," +
            "  title TEXT NOT NULL," +
            "  completed INTEGER DEFAULT 0," +
            "  sort_order INTEGER DEFAULT 0," +
            "  created_at INTEGER NOT NULL" +
            ")"
        );
        // ── Applets ─────────────────────────────────────────────
        tx.executeSql(
            "CREATE TABLE IF NOT EXISTS applets (" +
            "  id TEXT PRIMARY KEY," +
            "  name TEXT NOT NULL," +
            "  description TEXT DEFAULT ''," +
            "  html_content TEXT NOT NULL," +
            "  created_at INTEGER NOT NULL," +
            "  updated_at INTEGER NOT NULL" +
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
        return id;
    } catch (e) {
        console.error("saveMessage error:", e);
        return "";
    }
}

function updateMessageContent(db, messageId, newContent) {
    try {
        db.transaction(function (tx) {
            tx.executeSql(
                "UPDATE messages SET content = ? WHERE id = ?",
                [newContent, messageId]
            );
        });
    } catch (e) {
        console.error("updateMessageContent error:", e);
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

// ──────────────────────────────────────────────
// Task Groups CRUD
// ──────────────────────────────────────────────

function createTaskGroup(db, name, color) {
    var now = Date.now();
    var id = "grp_" + now.toString(36) + "_" + Math.random().toString(36).substr(2, 6);
    try {
        db.transaction(function (tx) {
            tx.executeSql(
                "INSERT INTO task_groups (id, name, color, sort_order, created_at) VALUES (?, ?, ?, 0, ?)",
                [id, name.trim(), color || "", now]
            );
        });
        return id;
    } catch (e) {
        console.error("createTaskGroup error:", e);
        return "";
    }
}

function loadTaskGroups(db) {
    var groups = [];
    try {
        db.readTransaction(function (tx) {
            var result = tx.executeSql(
                "SELECT * FROM task_groups ORDER BY sort_order ASC, created_at ASC"
            );
            for (var i = 0; i < result.rows.length; i++) {
                groups.push(result.rows.item(i));
            }
        });
    } catch (e) {
        console.error("loadTaskGroups error:", e);
    }
    return groups;
}

function findTaskGroupByName(db, name) {
    try {
        db.readTransaction(function (tx) {
            var result = tx.executeSql(
                "SELECT * FROM task_groups WHERE name = ? COLLATE NOCASE LIMIT 1",
                [name.trim()]
            );
            if (result.rows.length > 0) {
                return result.rows.item(0);
            }
        });
    } catch (e) {
        console.error("findTaskGroupByName error:", e);
    }
    return null;
}

function updateTaskGroup(db, groupId, name, color, sortOrder) {
    try {
        db.transaction(function (tx) {
            tx.executeSql(
                "UPDATE task_groups SET name = ?, color = ?, sort_order = ? WHERE id = ?",
                [name.trim(), color || "", sortOrder || 0, groupId]
            );
        });
    } catch (e) {
        console.error("updateTaskGroup error:", e);
    }
}

function deleteTaskGroup(db, groupId) {
    try {
        db.transaction(function (tx) {
            tx.executeSql("UPDATE tasks SET group_id = '' WHERE group_id = ?", [groupId]);
            tx.executeSql("DELETE FROM task_groups WHERE id = ?", [groupId]);
        });
    } catch (e) {
        console.error("deleteTaskGroup error:", e);
    }
}

// ──────────────────────────────────────────────
// Tasks CRUD
// ──────────────────────────────────────────────

function _parsePriority(val) {
    if (typeof val === "number") return val;
    var map = { "low": 1, "medium": 2, "med": 2, "high": 3 };
    return map[String(val).toLowerCase()] || 0;
}

function _parseDueDate(val) {
    if (!val) return null;
    if (typeof val === "number") return val;
    var str = String(val).trim();
    if (str === "") return null;
    var d = new Date(str);
    return isNaN(d.getTime()) ? null : d.getTime();
}

function saveTask(db, title, opts) {
    opts = opts || {};
    var now = Date.now();
    var id = "task_" + now.toString(36) + "_" + Math.random().toString(36).substr(2, 6);
    var groupId = opts.groupId || "";
    var description = opts.description || "";
    var status = opts.status || "pending";
    var priority = _parsePriority(opts.priority || 0);
    var dueDate = _parseDueDate(opts.dueDate);
    var recurrence = opts.recurrence || "";
    var sessionId = opts.sessionId || "";

    try {
        db.transaction(function (tx) {
            tx.executeSql(
                "INSERT INTO tasks (id, group_id, title, description, status, priority, due_date, recurrence, created_at, completed_at, source_session_id) " +
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?)",
                [id, groupId, title.trim(), description, status, priority, dueDate, recurrence, now, sessionId]
            );
        });
        return id;
    } catch (e) {
        console.error("saveTask error:", e);
        return "";
    }
}

function loadTasks(db, groupId) {
    var tasks = [];
    try {
        db.readTransaction(function (tx) {
            var result;
            if (groupId) {
                result = tx.executeSql(
                    "SELECT * FROM tasks WHERE group_id = ? ORDER BY priority DESC, due_date ASC NULLS LAST, created_at DESC",
                    [groupId]
                );
            } else {
                result = tx.executeSql(
                    "SELECT * FROM tasks ORDER BY priority DESC, due_date ASC NULLS LAST, created_at DESC"
                );
            }
            for (var i = 0; i < result.rows.length; i++) {
                tasks.push(result.rows.item(i));
            }
        });
    } catch (e) {
        console.error("loadTasks error:", e);
    }
    return tasks;
}

function loadTasksByStatus(db, status) {
    var tasks = [];
    try {
        db.readTransaction(function (tx) {
            var result = tx.executeSql(
                "SELECT * FROM tasks WHERE status = ? ORDER BY priority DESC, due_date ASC NULLS LAST, created_at DESC",
                [status]
            );
            for (var i = 0; i < result.rows.length; i++) {
                tasks.push(result.rows.item(i));
            }
        });
    } catch (e) {
        console.error("loadTasksByStatus error:", e);
    }
    return tasks;
}

function updateTaskStatus(db, taskId, status) {
    var now = Date.now();
    try {
        db.transaction(function (tx) {
            if (status === "done") {
                tx.executeSql(
                    "UPDATE tasks SET status = ?, completed_at = ? WHERE id = ?",
                    [status, now, taskId]
                );
            } else {
                tx.executeSql(
                    "UPDATE tasks SET status = ?, completed_at = NULL WHERE id = ?",
                    [status, taskId]
                );
            }
        });
    } catch (e) {
        console.error("updateTaskStatus error:", e);
    }
}

function updateTask(db, taskId, fields) {
    var sets = [];
    var vals = [];
    var allowed = ["group_id", "title", "description", "status", "priority", "due_date", "recurrence"];
    for (var i = 0; i < allowed.length; i++) {
        var key = allowed[i];
        if (fields.hasOwnProperty(key)) {
            sets.push(key + " = ?");
            vals.push(fields[key]);
        }
    }
    if (sets.length === 0) return;
    vals.push(taskId);
    try {
        db.transaction(function (tx) {
            tx.executeSql("UPDATE tasks SET " + sets.join(", ") + " WHERE id = ?", vals);
        });
    } catch (e) {
        console.error("updateTask error:", e);
    }
}

function deleteTask(db, taskId) {
    try {
        db.transaction(function (tx) {
            tx.executeSql("DELETE FROM subtasks WHERE task_id = ?", [taskId]);
            tx.executeSql("DELETE FROM tasks WHERE id = ?", [taskId]);
        });
    } catch (e) {
        console.error("deleteTask error:", e);
    }
}

function getTask(db, taskId) {
    try {
        db.readTransaction(function (tx) {
            var result = tx.executeSql("SELECT * FROM tasks WHERE id = ? LIMIT 1", [taskId]);
            if (result.rows.length > 0) {
                return result.rows.item(0);
            }
        });
    } catch (e) {
        console.error("getTask error:", e);
    }
    return null;
}

// ──────────────────────────────────────────────
// Subtasks CRUD
// ──────────────────────────────────────────────

function saveSubtask(db, taskId, title) {
    var now = Date.now();
    var id = "sub_" + now.toString(36) + "_" + Math.random().toString(36).substr(2, 6);
    try {
        db.transaction(function (tx) {
            tx.executeSql(
                "INSERT INTO subtasks (id, task_id, title, completed, sort_order, created_at) VALUES (?, ?, ?, 0, 0, ?)",
                [id, taskId, title.trim(), now]
            );
        });
        return id;
    } catch (e) {
        console.error("saveSubtask error:", e);
        return "";
    }
}

function loadSubtasks(db, taskId) {
    var subs = [];
    try {
        db.readTransaction(function (tx) {
            var result = tx.executeSql(
                "SELECT * FROM subtasks WHERE task_id = ? ORDER BY sort_order ASC, created_at ASC",
                [taskId]
            );
            for (var i = 0; i < result.rows.length; i++) {
                subs.push(result.rows.item(i));
            }
        });
    } catch (e) {
        console.error("loadSubtasks error:", e);
    }
    return subs;
}

function updateSubtaskStatus(db, subtaskId, completed) {
    try {
        db.transaction(function (tx) {
            tx.executeSql(
                "UPDATE subtasks SET completed = ? WHERE id = ?",
                [completed ? 1 : 0, subtaskId]
            );
        });
    } catch (e) {
        console.error("updateSubtaskStatus error:", e);
    }
}

function deleteSubtask(db, subtaskId) {
    try {
        db.transaction(function (tx) {
            tx.executeSql("DELETE FROM subtasks WHERE id = ?", [subtaskId]);
        });
    } catch (e) {
        console.error("deleteSubtask error:", e);
    }
}

// ──────────────────────────────────────────────
// Applets CRUD
// ──────────────────────────────────────────────

function createApplet(db, name, description, htmlContent) {
    var now = Date.now();
    var id = "applet_" + now.toString(36) + "_" + Math.random().toString(36).substr(2, 6);
    try {
        db.transaction(function (tx) {
            tx.executeSql(
                "INSERT INTO applets (id, name, description, html_content, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
                [id, name.trim(), description || "", htmlContent, now, now]
            );
        });
        return id;
    } catch (e) {
        console.error("createApplet error:", e);
        return "";
    }
}

function listApplets(db) {
    var applets = [];
    try {
        db.readTransaction(function (tx) {
            var result = tx.executeSql(
                "SELECT id, name, description, created_at, updated_at FROM applets ORDER BY updated_at DESC"
            );
            for (var i = 0; i < result.rows.length; i++) {
                applets.push(result.rows.item(i));
            }
        });
    } catch (e) {
        console.error("listApplets error:", e);
    }
    return applets;
}

function getApplet(db, appletId) {
    try {
        db.readTransaction(function (tx) {
            var result = tx.executeSql("SELECT * FROM applets WHERE id = ? LIMIT 1", [appletId]);
            if (result.rows.length > 0) {
                return result.rows.item(0);
            }
        });
    } catch (e) {
        console.error("getApplet error:", e);
    }
    return null;
}

function updateApplet(db, appletId, name, description, htmlContent) {
    var now = Date.now();
    try {
        db.transaction(function (tx) {
            tx.executeSql(
                "UPDATE applets SET name = ?, description = ?, html_content = ?, updated_at = ? WHERE id = ?",
                [name.trim(), description || "", htmlContent, now, appletId]
            );
        });
    } catch (e) {
        console.error("updateApplet error:", e);
    }
}

function deleteApplet(db, appletId) {
    try {
        db.transaction(function (tx) {
            tx.executeSql("DELETE FROM applets WHERE id = ?", [appletId]);
        });
    } catch (e) {
        console.error("deleteApplet error:", e);
    }
}
