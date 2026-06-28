#!/usr/bin/env python3
"""
KDE Assistant — Webserver Daemon
Production-grade HTTP server for mobile web UI and REST API.
"""

import os
import re
import sys
import json
import sqlite3
import signal
import argparse
import logging
import hashlib
import urllib.request
import urllib.parse
import time
import subprocess
import datetime
import shlex
import threading
from collections import defaultdict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# ──────────────────────────────────────────────
# Logging
# ──────────────────────────────────────────────

logger = logging.getLogger("kdeassistant")

# ──────────────────────────────────────────────
# Rate limiter
# ──────────────────────────────────────────────

class RateLimiter:
    def __init__(self, max_requests=60, window_seconds=60):
        self._max_requests = max_requests
        self._window = window_seconds
        self._requests = defaultdict(list)
        self._lock = threading.Lock()

    def is_allowed(self, key):
        now = time.time()
        with self._lock:
            timestamps = self._requests[key]
            cutoff = now - self._window
            self._requests[key] = [t for t in timestamps if t > cutoff]
            if len(self._requests[key]) >= self._max_requests:
                return False
            self._requests[key].append(now)
            return True

# ──────────────────────────────────────────────
# Constants
# ──────────────────────────────────────────────

DB_VERSION = 2
MAX_REQUEST_BODY = 10 * 1024 * 1024  # 10 MB
PID_FILE = "/tmp/kdeassistant_webserver.pid"

RATE_LIMITER = RateLimiter(max_requests=120, window_seconds=60)

MIME_TYPES = {
    '.html': 'text/html; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.js': 'application/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2',
    '.ttf': 'font/ttf',
    '.otf': 'font/otf',
    '.eot': 'application/vnd.ms-fontobject',
    '.txt': 'text/plain; charset=utf-8',
    '.md': 'text/markdown; charset=utf-8',
    '.xml': 'application/xml',
    '.pdf': 'application/pdf',
}

# ──────────────────────────────────────────────
# Hijri calendar (local, no API dependency)
# ──────────────────────────────────────────────

def gregorian_to_jdn(year, month, day):
    a = (14 - month) // 12
    y = year + 4800 - a
    m = month + 12 * a - 3
    return day + (153 * m + 2) // 5 + 365 * y + y // 4 - y // 100 + y // 400 - 32045

def jdn_to_hijri(jdn):
    l = jdn - 1948440 + 10632
    n = (l - 1) // 10631
    remainder = l - 10631 * n + 354
    j = ((10985 - remainder) // 5316) * ((50 * remainder) // 17719) + \
        (remainder // 5670) * ((43 * remainder) // 15238)
    remainder = remainder - ((30 - j) // 15) * ((17719 * j) // 50) - \
                (j // 16) * ((15238 * j) // 43) + 29
    month = (24 * remainder) // 709
    day = remainder - (709 * month) // 24
    year = 30 * n + j - 30
    return year, month, day

HIJRI_MONTHS = [
    "Muharram", "Safar", "Rabi al-Awwal", "Rabi al-Thani",
    "Jumada al-Ula", "Jumada al-Thani", "Rajab", "Sha'ban",
    "Ramadan", "Shawwal", "Dhu al-Qa'dah", "Dhu al-Hijjah"
]

GREG_DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
GREG_MONTHS = ["January", "February", "March", "April", "May", "June",
               "July", "August", "September", "October", "November", "December"]

def get_hijri_date(dt):
    jdn = gregorian_to_jdn(dt.year, dt.month, dt.day)
    year, month, day = jdn_to_hijri(jdn)
    month_name = HIJRI_MONTHS[month - 1] if 1 <= month <= 12 else ""
    return day, month_name, year

def get_gregorian_date(dt):
    day_name = GREG_DAYS[dt.weekday()]
    month_name = GREG_MONTHS[dt.month - 1]
    tz_str = ""
    try:
        tz_str = dt.astimezone().tzname() or ""
    except Exception:
        pass
    tz_part = f" ({tz_str})" if tz_str else ""
    return f"{day_name}, {dt.day} {month_name} {dt.year}, {dt.hour:02d}:{dt.minute:02d}{tz_part}"

def build_date_time_context():
    now = datetime.datetime.now()
    greg_full = get_gregorian_date(now)
    h_day, h_month, h_year = get_hijri_date(now)
    return f"## Current Date & Time\nGregorian: {greg_full}\nHijri: {h_day} {h_month} {h_year} AH"

def build_prayer_times_instructions(lat, lng, method):
    try:
        lat_val = float(lat) if lat not in (None, "") else None
        lng_val = float(lng) if lng not in (None, "") else None
    except ValueError:
        lat_val = None
        lng_val = None

    if lat_val is not None and lng_val is not None:
        location_line = f"User's default location: latitude={lat_val}, longitude={lng_val}\n"
    else:
        location_line = "User's default location: not configured. Ask the user for their city or coordinates.\n"

    try:
        method_val = int(method) if method not in (None, "") else None
    except ValueError:
        method_val = None

    method_names = {
        1: "University of Islamic Sciences, Karachi",
        2: "Muslim World League (MWL)",
        3: "Islamic Society of North America (ISNA)",
        4: "Umm Al-Qura University, Makkah",
        5: "Egyptian General Authority of Survey",
        7: "Institute of Geophysics, University of Tehran",
        8: "Gulf Region",
        9: "Kuwait",
        10: "Qatar",
        11: "MUIS, Singapore",
        12: "UOIF, France",
        13: "Diyanet, Turkey",
        15: "Moonsighting Committee Worldwide"
    }

    if method_val is not None and method_val > 0:
        method_name = method_names.get(method_val, "Unknown")
        method_line = f"Default calculation method: {method_val} ({method_name})\n"
    else:
        method_line = "Default calculation method: not configured. Use method 3 (ISNA) as fallback.\n"

    return "\n## Prayer Times (Islamic)\n" + \
           "To fetch prayer times for the user, use the [FETCH:] tool with the AlAdhan API.\n" + \
           "URL format: https://api.aladhan.com/v1/timings/today?latitude={lat}&longitude={lng}&method={method}\n\n" + \
           location_line + \
           method_line + \
           "Calculation methods:\n" + \
           "  2 = Muslim World League (MWL)\n" + \
           "  3 = Islamic Society of North America (ISNA)\n" + \
           "  4 = Umm Al-Qura University, Makkah\n" + \
           "  5 = Egyptian General Authority of Survey\n" + \
           "  7 = Institute of Geophysics, University of Tehran\n" + \
           "  8 = Gulf Region\n" + \
           "  9 = Kuwait\n" + \
           "  10 = Qatar\n" + \
           "  11 = MUIS, Singapore\n" + \
           "  13 = Diyanet, Turkey\n" + \
           "  15 = Moonsighting Committee Worldwide\n\n" + \
           "Examples:\n" + \
           "  [FETCH: https://api.aladhan.com/v1/timings/today?latitude=52.52&longitude=13.405&method=3]\n" + \
           "  [FETCH: https://api.aladhan.com/v1/timings/2026-06-19?latitude=21.4225&longitude=39.8262&method=4]\n\n" + \
           "For monthly timetable, use:\n" + \
           "  https://api.aladhan.com/v1/calendar/{year}/{month}?latitude={lat}&longitude={lng}&method={method}\n\n" + \
           "The API returns JSON with a 'data.timings' object containing: Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha, and others.\n" + \
           "Format the response as a clean table or list for the user."

# ──────────────────────────────────────────────
# Database helpers
# ──────────────────────────────────────────────

def open_db_with_retry(db_path, retries=5, delay=0.1):
    for attempt in range(retries):
        try:
            conn = sqlite3.connect(db_path, timeout=30.0)
            conn.execute("PRAGMA journal_mode=WAL")
            conn.execute("PRAGMA busy_timeout=5000")
            return conn
        except sqlite3.OperationalError as e:
            if "locked" in str(e) and attempt < retries - 1:
                time.sleep(delay * (attempt + 1))
            else:
                raise

def load_memories_from_db(db_path):
    memories = []
    try:
        conn = open_db_with_retry(db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT content FROM memories ORDER BY created_at ASC")
        rows = cursor.fetchall()
        for r in rows:
            memories.append(r[0])
        conn.close()
    except Exception as e:
        logger.warning("Failed to load memories: %s", e)
    return memories

def run_db_migrations(conn):
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='schema_version'")
    if not cursor.fetchone():
        cursor.execute("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY)")
        cursor.execute("INSERT INTO schema_version (version) VALUES (?)", (DB_VERSION,))
        conn.commit()
        return
    cursor.execute("SELECT version FROM schema_version LIMIT 1")
    row = cursor.fetchone()
    current_version = row[0] if row else 0
    if current_version < DB_VERSION:
        _migrate_db(conn, current_version, DB_VERSION)

def _migrate_db(conn, from_ver, to_ver):
    cursor = conn.cursor()
    if from_ver < 2:
        try:
            cursor.execute("ALTER TABLE memories ADD COLUMN source_session_id TEXT")
        except sqlite3.OperationalError:
            pass
        try:
            cursor.execute("ALTER TABLE tasks ADD COLUMN completed_at INTEGER")
        except sqlite3.OperationalError:
            pass
    cursor.execute("UPDATE schema_version SET version = ?", (to_ver,))
    conn.commit()
    logger.info("Database migrated from version %d to %d", from_ver, to_ver)

def find_sqlite_db(custom_path=None):
    if custom_path and os.path.exists(custom_path):
        return custom_path

    home = os.path.expanduser("~")
    app_data_dir = os.path.join(home, ".local", "share", "kdeassistant")
    os.makedirs(app_data_dir, exist_ok=True)
    primary_path = os.path.join(app_data_dir, "chat.db")
    if os.path.exists(primary_path):
        return primary_path

    host_name = None
    curr_pid = os.getpid()
    for _ in range(5):
        try:
            with open(f"/proc/{curr_pid}/status", "r") as f:
                ppid = None
                for line in f:
                    if line.startswith("PPid:"):
                        ppid = int(line.split()[1])
                        break
            if not ppid or ppid <= 1:
                break
            with open(f"/proc/{ppid}/cmdline", "r") as f:
                cmdline = f.read().lower()
                if "plasmoidviewer" in cmdline:
                    host_name = "plasmoidviewer"
                    break
                elif "plasmawindowed" in cmdline:
                    host_name = "plasmawindowed"
                    break
                elif "plasmashell" in cmdline:
                    host_name = "plasmashell"
                    break
            curr_pid = ppid
        except Exception:
            break

    logger.info("Detected QML host process: %s", host_name)

    search_dirs = []
    if host_name:
        search_dirs.append(os.path.join(home, f".local/share/{host_name}/QML/OfflineStorage/Databases"))
    for dname in ["plasmashell", "plasmawindowed", "plasmoidviewer"]:
        if dname != host_name:
            search_dirs.append(os.path.join(home, f".local/share/{dname}/QML/OfflineStorage/Databases"))

    db_filename = "0a6708d6d2377187561fdb538e34d70d.sqlite"
    for d in search_dirs:
        path = os.path.join(d, db_filename)
        if os.path.exists(path):
            try:
                import shutil
                shutil.copy2(path, primary_path)
                logger.info("Migrated legacy DB to %s", primary_path)
            except Exception as e:
                logger.warning("Failed to migrate legacy DB: %s", e)
            return path

    for root, dirs, files in os.walk(os.path.join(home, ".local/share")):
        if db_filename in files:
            found = os.path.join(root, db_filename)
            try:
                import shutil
                shutil.copy2(found, primary_path)
                logger.info("Migrated legacy DB to %s", primary_path)
            except Exception:
                pass
            return found

    logger.info("Using new database at %s", primary_path)
    return primary_path

# ──────────────────────────────────────────────
# Parse commands from assistant response
# ──────────────────────────────────────────────

def parse_command_tag(text):
    if not text:
        return None

    clean = re.sub(r'<thinking>[\s\S]*?</thinking>', '', text, flags=re.IGNORECASE).strip()
    if not clean:
        return None

    sys_match = re.search(r'\[system:\s*([^\]]+)\]', clean, re.IGNORECASE)
    if sys_match:
        return {"type": "system", "command": sys_match.group(1).strip()}

    opencode_match = re.search(r'\[opencode:\s*([^\]]+)\]', clean, re.IGNORECASE)
    if opencode_match:
        raw = opencode_match.group(1).strip()
        files_match = re.search(r'\bfiles="([^"]+)"', raw, re.IGNORECASE)
        model_match = re.search(r'\bmodel="([^"]+)"', raw, re.IGNORECASE)
        instruction_end = re.search(r'\s+(?:files|model)=', raw, re.IGNORECASE)
        if instruction_end:
            instruction = raw[:instruction_end.start()].strip()
        else:
            instruction = raw
        return {
            "type": "opencode",
            "instruction": instruction,
            "files": files_match.group(1) if files_match else "",
            "model": model_match.group(1) if model_match else ""
        }

    grep_match = re.search(r'\[grep:\s*"([^"]+)"\s*"([^"]+)"\]', clean, re.IGNORECASE) or \
                 re.search(r'\[grep:\s*([^\s\]]+)\s*([^\s\]]+)\]', clean, re.IGNORECASE)
    if grep_match:
        return {"type": "grep", "pattern": grep_match.group(1), "path": grep_match.group(2)}

    setting_match = re.search(r'\[setting:\s*([\s\S]+?)\s+description="([^"]+)"\]', clean, re.IGNORECASE)
    if setting_match:
        return {"type": "setting", "command": setting_match.group(1).strip(), "description": setting_match.group(2).strip()}

    remember_match = re.search(r'\[remember:\s*([\s\S]+?)\s*\]', clean, re.IGNORECASE)
    if remember_match:
        return {"type": "remember", "content": remember_match.group(1).strip()}

    add_task_match = re.search(r'\[add_task:\s*([^\]]+)\]', clean, re.IGNORECASE)
    if add_task_match:
        raw = add_task_match.group(1).strip()
        group_match = re.search(r'\bgroup="([^"]+)"', raw, re.IGNORECASE)
        priority_match = re.search(r'\bpriority=(\w+)', raw, re.IGNORECASE)
        due_match = re.search(r'\bdue="([^"]+)"', raw, re.IGNORECASE)
        desc_match = re.search(r'\bdescription="([^"]+)"', raw, re.IGNORECASE)
        recur_match = re.search(r'\brecurrence=(\w+)', raw, re.IGNORECASE)
        title_end_match = re.search(r'\s+(?:group|priority|due|description|recurrence)=', raw, re.IGNORECASE)
        if title_end_match:
            title = raw[:title_end_match.start()].strip()
        else:
            title = raw
        return {
            "type": "add_task",
            "title": title,
            "group": group_match.group(1) if group_match else "",
            "priority": priority_match.group(1) if priority_match else "none",
            "due": due_match.group(1) if due_match else "",
            "description": desc_match.group(1) if desc_match else "",
            "recurrence": recur_match.group(1) if recur_match else ""
        }

    task_match = re.search(r'\[task:\s*([^\]]+)\]', clean, re.IGNORECASE)
    if task_match:
        return {
            "type": "task",
            "title": task_match.group(1).strip(),
            "group": "",
            "priority": "none",
            "due": "",
            "description": "",
            "recurrence": ""
        }
    return None

# ──────────────────────────────────────────────
# Input validation helpers
# ──────────────────────────────────────────────

def validate_id(value, name="id"):
    if not value or not isinstance(value, str):
        return None
    if len(value) > 256 or not re.match(r'^[a-zA-Z0-9_\-\.]+$', value):
        logger.warning("Invalid %s rejected: %s", name, value[:50])
        return None
    return value

def validate_string(value, name, max_len=10000, required=False):
    if value is None or value == "":
        if required:
            return None
        return ""
    if not isinstance(value, str):
        return None
    if len(value) > max_len:
        logger.warning("String too long for %s (%d > %d)", name, len(value), max_len)
        return None
    return value

def validate_action(value):
    if value in ("approve", "decline"):
        return value
    return None

# ──────────────────────────────────────────────
# HTTP Handler
# ──────────────────────────────────────────────

class WebServerHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        logger.info(format, *args)

    def _send_json(self, status, data):
        body = json.dumps(data).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self._send_cors_headers()
        self.end_headers()
        self.wfile.write(body)

    def _send_error_json(self, status, message):
        self._send_json(status, {"error": message})

    def _send_cors_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
        self.send_header('Access-Control-Max-Age', '86400')

    def check_auth(self):
        parsed_url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(parsed_url.query)
        token = query.get('token', [None])[0]

        if not token:
            auth_header = self.headers.get('Authorization')
            if auth_header and auth_header.startswith('Bearer '):
                token = auth_header[7:]

        if token and token == self.server.token:
            return True

        self._send_error_json(401, "Unauthorized")
        return False

    def do_OPTIONS(self):
        self.send_response(204)
        self._send_cors_headers()
        self.end_headers()

    def do_GET(self):
        parsed_url = urllib.parse.urlparse(self.path)
        path = parsed_url.path

        if path.startswith('/api/'):
            if not self.check_auth():
                return
            if path == '/api/sessions':
                self.handle_get_sessions()
            elif path == '/api/messages':
                self.handle_get_messages(parsed_url.query)
            elif path == '/api/tasks':
                self.handle_get_tasks()
            elif path == '/api/memories':
                self.handle_get_memories()
            else:
                self._send_error_json(404, "API endpoint not found")
            return

        if path == '/':
            path = '/index.html'

        safe_path = os.path.normpath(path).lstrip('/')
        if '..' in safe_path:
            self._send_error_json(403, "Forbidden")
            return

        file_path = os.path.join(self.server.static_dir, safe_path)

        if not file_path.startswith(self.server.static_dir) or not os.path.exists(file_path) or os.path.isdir(file_path):
            if safe_path.startswith('code/') or safe_path.startswith('contents/code/'):
                base_dir = os.path.dirname(self.server.static_dir)
                code_path = os.path.join(base_dir, safe_path.replace('contents/', ''))
                if os.path.exists(code_path):
                    file_path = code_path
                else:
                    self._send_error_json(404, "File not found")
                    return
            else:
                self._send_error_json(404, "File not found")
                return

        ext = os.path.splitext(file_path)[1].lower()
        mime = MIME_TYPES.get(ext, 'application/octet-stream')

        try:
            with open(file_path, 'rb') as f:
                content = f.read()
            self.send_response(200)
            self.send_header('Content-Type', mime)
            self.send_header('Content-Length', str(len(content)))
            self._send_cors_headers()
            self.end_headers()
            self.wfile.write(content)
        except Exception as e:
            logger.error("Failed to serve %s: %s", file_path, e)
            self._send_error_json(500, "Internal server error")

    def do_POST(self):
        parsed_url = urllib.parse.urlparse(self.path)
        path = parsed_url.path

        if not self.check_auth():
            return

        content_length = int(self.headers.get('Content-Length', 0))
        if content_length > MAX_REQUEST_BODY:
            self._send_error_json(413, "Request body too large")
            return

        post_data = self.rfile.read(content_length) if content_length > 0 else b'{}'
        try:
            data = json.loads(post_data.decode('utf-8'))
        except Exception:
            data = {}

        if path == '/api/messages':
            self.handle_post_message(data)
        elif path == '/api/proxy/chat/completions':
            self.handle_proxy_chat_completions(data)
        elif path == '/api/proxy/abort':
            self.handle_proxy_abort(data)
        elif path == '/api/tasks/toggle':
            self.handle_tasks_toggle(data)
        elif path == '/api/memories/delete':
            self.handle_memories_delete(data)
        elif path == '/api/commands/action':
            self.handle_commands_action(data)
        else:
            self._send_error_json(404, "API endpoint not found")

    def handle_get_sessions(self):
        conn = open_db_with_retry(self.server.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("SELECT id, title, created_at, updated_at FROM sessions ORDER BY updated_at DESC LIMIT 50")
        rows = cursor.fetchall()
        sessions = [dict(r) for r in rows]
        conn.close()
        self._send_json(200, sessions)

    def handle_get_messages(self, query_str):
        query = urllib.parse.parse_qs(query_str)
        session_id = query.get('session_id', [None])[0]
        session_id = validate_id(session_id, "session_id")
        if not session_id:
            self._send_error_json(400, "Missing or invalid session_id")
            return

        conn = open_db_with_retry(self.server.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("SELECT id, role, content, timestamp FROM messages WHERE session_id = ? ORDER BY timestamp ASC", (session_id,))
        rows = cursor.fetchall()
        messages = [dict(r) for r in rows]
        conn.close()
        self._send_json(200, messages)

    def handle_proxy_abort(self, data):
        parsed_url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(parsed_url.query)
        request_id = query.get('request_id', [None])[0]
        logger.info(f"PROXY: Received abort request for request_id: {request_id}")
        if request_id:
            response = self.server.active_requests.pop(request_id, None)
            if response:
                try:
                    response.close()
                    logger.info(f"PROXY: Successfully closed response for request_id: {request_id}")
                except Exception as e:
                    logger.error(f"PROXY: Error closing response: {e}")
        self.send_response(200)
        self._send_cors_headers()
        self.end_headers()
        try:
            self.wfile.write(json.dumps({"status": "aborted"}).encode('utf-8'))
        except Exception:
            pass

    def handle_proxy_chat_completions(self, data):
        parsed_url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(parsed_url.query)
        request_id = query.get('request_id', [None])[0]
        logger.info(f"PROXY: Starting stream for request_id: {request_id}")

        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Connection', 'close')
        self._send_cors_headers()
        self.end_headers()
        self.wfile.flush()

        api_url = self.server.llm_args.get('api_url', "http://localhost:11434/v1")
        api_key = self.server.llm_args.get('api_key', "")
        
        if api_url.endswith('/'):
            api_url = api_url[:-1]
        endpoint = f"{api_url}/chat/completions"

        data["stream"] = True

        req = urllib.request.Request(endpoint, data=json.dumps(data).encode('utf-8'))
        req.add_header('Content-Type', 'application/json')
        req.add_header('Connection', 'close')
        if api_key:
            req.add_header('Authorization', f'Bearer {api_key}')

        # Build opener that ignores system proxies for local loopback
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        try:
            with opener.open(req, timeout=300) as response:
                if request_id:
                    self.server.active_requests[request_id] = response
                try:
                    for line in response:
                        if not line.strip():
                            continue
                        line_str = line.decode('utf-8').strip()
                        if line_str.startswith('data: '):
                            data_content = line_str[6:]
                            if data_content == '[DONE]':
                                self.wfile.write(b"data: [DONE]\n\n")
                                self.wfile.flush()
                                break
                            try:
                                chunk = json.loads(data_content)
                                self.wfile.write(f"data: {json.dumps(chunk)}\n\n".encode('utf-8'))
                                self.wfile.flush()
                            except (ConnectionError, BrokenPipeError, OSError):
                                logger.info("Proxy client disconnected. Stopping stream.")
                                break
                            except Exception:
                                pass
                finally:
                    if request_id:
                        self.server.active_requests.pop(request_id, None)
        except Exception as e:
            logger.error("Error in proxy_chat_completions: %s", e)
            err_msg = f"Error: {str(e)}"
            try:
                self.wfile.write(f"data: {json.dumps({'error': err_msg})}\n\n".encode('utf-8'))
            except Exception:
                pass

    def handle_post_message(self, data):
        session_id = data.get('session_id')
        prompt = data.get('prompt')

        if session_id:
            session_id = validate_id(session_id, "session_id")
        prompt = validate_string(prompt, "prompt", max_len=100000, required=True)
        if not prompt:
            self._send_error_json(400, "Missing or invalid prompt")
            return

        now = int(time.time() * 1000)
        conn = open_db_with_retry(self.server.db_path)
        cursor = conn.cursor()

        if not session_id:
            session_id = f"sess_{now}"
            cursor.execute("INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)",
                           (session_id, prompt[:25] + ("..." if len(prompt) > 25 else ""), now, now))

        user_msg_id = f"msg_user_{now}"
        cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                       (user_msg_id, session_id, "user", prompt, now))
        cursor.execute("UPDATE sessions SET updated_at = ? WHERE id = ?", (now, session_id))
        conn.commit()

        cursor.execute("SELECT role, content FROM messages WHERE session_id = ? ORDER BY timestamp ASC", (session_id,))
        history = [{"role": r[0], "content": r[1]} for r in cursor.fetchall()]
        conn.close()

        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Connection', 'keep-alive')
        self._send_cors_headers()
        self.end_headers()
        self.wfile.flush()

        try:
            full_response = self.stream_llm(history)
            cmd_tag = parse_command_tag(full_response)

            conn = open_db_with_retry(self.server.db_path)
            cursor = conn.cursor()
            assistant_now = int(time.time() * 1000)

            if cmd_tag:
                self._process_cmd_tag(cursor, cmd_tag, full_response, session_id, assistant_now)

            cursor.execute("UPDATE sessions SET updated_at = ? WHERE id = ?", (assistant_now, session_id))
            conn.commit()
            conn.close()
        except Exception as e:
            logger.error("Error in stream_llm: %s", e)
            err_msg = f"Error: {str(e)}"
            self.wfile.write(f"data: {json.dumps({'error': err_msg})}\n\n".encode('utf-8'))

    def _process_cmd_tag(self, cursor, cmd_tag, full_response, session_id, now):
        if cmd_tag["type"] == "remember":
            mem_content = cmd_tag["content"]
            clean_response = re.sub(r'\[remember:\s*[\s\S]+?\]', '', full_response, flags=re.IGNORECASE).strip()
            if not clean_response:
                clean_response = f"Got it! I will remember: \"{mem_content}\""
            mem_id = f"mem_{now}_{os.urandom(4).hex()}"
            try:
                cursor.execute("INSERT INTO memories (id, content, created_at, source_session_id) VALUES (?, ?, ?, ?)",
                               (mem_id, mem_content, now, session_id))
                cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                               (f"msg_mem_{now}", session_id, "memory", json.dumps({"id": mem_id, "content": mem_content}), now))
                cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                               (f"msg_assistant_{now}_text", session_id, "assistant", clean_response, now + 1))
                subprocess.run(["notify-send", "-i", "dialog-information", "KDE Assistant", f"Memory Saved: {mem_content}"], capture_output=True)
            except Exception as e:
                logger.error("Failed to save memory: %s", e)
                cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                               (f"msg_mem_{now}_err", session_id, "error", "Failed to save memory: database error.", now))

        elif cmd_tag["type"] in ("task", "add_task"):
            self._process_task_cmd(cursor, cmd_tag, full_response, session_id, now)

        elif cmd_tag["type"] == "system":
            command = cmd_tag["command"]
            clean_response = re.sub(r'\[system:\s*[\s\S]+?\]', '', full_response, flags=re.IGNORECASE).strip()
            if not clean_response:
                clean_response = f"Executing system command: `{command}`"
            cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                           (f"msg_cmd_{now}", session_id, "system_command",
                            json.dumps({"command": command, "output": "", "status": "pending"}), now))
            cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                           (f"msg_assistant_{now}_text", session_id, "assistant", clean_response, now + 1))

        elif cmd_tag["type"] == "grep":
            pattern = cmd_tag["pattern"]
            path = cmd_tag["path"]
            clean_response = re.sub(r'\[grep:\s*[\s\S]+?\]', '', full_response, flags=re.IGNORECASE).strip()
            if not clean_response:
                clean_response = f"Searching for pattern: `{pattern}`"
            grep_cmd = f"rg -n --color=never {shlex.quote(pattern)} {shlex.quote(path)} || grep -rnI {shlex.quote(pattern)} {shlex.quote(path)}"
            try:
                result = subprocess.run(grep_cmd, shell=True, capture_output=True, text=True, timeout=15)
                output = result.stdout
                if result.stderr:
                    output += "\n" + result.stderr
                status = "completed" if result.returncode == 0 else "error"
            except Exception as e:
                output = str(e)
                status = "error"
            cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                           (f"msg_grep_{now}", session_id, "system_command",
                            json.dumps({"command": grep_cmd, "output": output, "status": status, "displayPattern": pattern}), now))
            cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                           (f"msg_assistant_{now}_text", session_id, "assistant", clean_response, now + 1))

        elif cmd_tag["type"] == "setting":
            command = cmd_tag["command"]
            description = cmd_tag["description"]
            clean_response = re.sub(r'\[setting:\s*[\s\S]+?\]', '', full_response, flags=re.IGNORECASE).strip()
            if not clean_response:
                clean_response = f"Requested settings change: {description}"
            cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                           (f"msg_setting_{now}", session_id, "setting_approval", f"{command}\n\n{description}", now))
            cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                           (f"msg_assistant_{now}_text", session_id, "assistant", clean_response, now + 1))

        elif cmd_tag["type"] == "opencode":
            instruction = cmd_tag["instruction"]
            files = cmd_tag["files"]
            model = cmd_tag["model"]
            clean_response = re.sub(r'\[opencode:\s*[\s\S]+?\]', '', full_response, flags=re.IGNORECASE).strip()
            if not clean_response:
                clean_response = f"Requested OpenCode run: {instruction}"
            op_data = json.dumps({"instruction": instruction, "files": files, "model": model})
            cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                           (f"msg_opencode_{now}", session_id, "opencode_approval", op_data, now))
            cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                           (f"msg_assistant_{now}_text", session_id, "assistant", clean_response, now + 1))

    def _process_task_cmd(self, cursor, cmd_tag, full_response, session_id, now):
        task_title = cmd_tag["title"]
        group_name = cmd_tag["group"]
        priority_str = cmd_tag["priority"]
        due_str = cmd_tag["due"]
        description = cmd_tag["description"]
        recurrence = cmd_tag["recurrence"]
        clean_response = re.sub(r'\[(?:add_)?task:\s*[\s\S]+?\]', '', full_response, flags=re.IGNORECASE).strip()
        if not clean_response:
            clean_response = f"I've added the task: \"{task_title}\""
        try:
            group_id = ""
            if group_name:
                cursor.execute("SELECT id FROM task_groups WHERE name = ?", (group_name,))
                group_row = cursor.fetchone()
                if group_row:
                    group_id = group_row[0]
                else:
                    group_id = f"group_{now}"
                    cursor.execute("INSERT INTO task_groups (id, name, created_at) VALUES (?, ?, ?)",
                                   (group_id, group_name, now))
            priority_val = {"high": 3, "medium": 2, "low": 1}.get(priority_str, 0)
            due_date = None
            if due_str:
                try:
                    from datetime import datetime
                    dt = datetime.fromisoformat(due_str.replace('Z', '+00:00'))
                    due_date = int(dt.timestamp() * 1000)
                except Exception:
                    pass
            task_id = f"task_{now}_{os.urandom(4).hex()}"
            cursor.execute("INSERT INTO tasks (id, group_id, title, description, status, priority, due_date, recurrence, created_at, source_session_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                           (task_id, group_id, task_title, description, 'pending', priority_val, due_date, recurrence, now, session_id))
            cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                           (f"msg_task_{now}", session_id, "task", json.dumps({"id": task_id, "title": task_title}), now))
            cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                           (f"msg_assistant_{now}_text", session_id, "assistant", clean_response, now + 1))
            subprocess.run(["notify-send", "-i", "dialog-information", "KDE Assistant", f"Task Created: {task_title}"], capture_output=True)
        except Exception as e:
            logger.error("Failed to create task: %s", e)
            cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                           (f"msg_task_{now}_err", session_id, "error", "Failed to create task: database error.", now))

    def stream_llm(self, history):
        base_prompt = self.server.llm_args.get('system_prompt', "You are a helpful assistant.")
        if not base_prompt or not base_prompt.strip():
            base_prompt = "You are a helpful assistant."
        base_prompt = base_prompt.strip()

        date_time_context = build_date_time_context()
        base_prompt = date_time_context + "\n\n" + base_prompt

        base_prompt += "\n\n" + \
            "CRITICAL INSTRUCTIONS FOR TOOL USAGE:\n" + \
            "You have access to local system integration tools. To run a tool, you must output a single command tag in brackets and STOP writing. Do not add any introduction, explanations, or concluding conversational text in the same turn.\n" + \
            "IMPORTANT: NEVER use bracketed placeholder symbols (like `<url>`, `<command>`, `<pattern>`, or `<path>`) literally. Replace them with real, concrete values.\n\n" + \
            "1. Webpage Content Fetching:\n" + \
            "   Format: `[FETCH: URL]`\n\n" + \
            "2. Local File Search:\n" + \
            "   Format: `[GREP: \"pattern\" \"path\"]`\n\n" + \
            "3. Read-Only System Info & Directory Listing:\n" + \
            "   Format: `[SYSTEM: COMMAND]`\n" + \
            "   Approved commands: ls, find, cat, free -h, uname -a, df -h, uptime, lscpu, lsusb, lspci, ps aux, systemctl status <service>, pactl list, qdbus, dmesg | tail\n\n" + \
            "4. Modifying KDE Settings:\n" + \
            "   Format: `[SETTING: COMMAND description=\"DESCRIPTION\"]`\n\n" + \
            "5. Clickable Local Links:\n" + \
            "   Format: `[Link Text](file:///absolute/path)`\n\n" + \
            "6. Saving a Memory:\n" + \
            "   Format: `[REMEMBER: fact to remember]`\n\n" + \
            "7. OpenCode Autonomous Coding Agent:\n" + \
            "   Format: `[opencode: instruction files=\"file1,file2\" model=\"model_name\"]`"

        lat = self.server.llm_args.get('prayer_latitude', '')
        lng = self.server.llm_args.get('prayer_longitude', '')
        method = self.server.llm_args.get('prayer_method', '3')
        base_prompt += build_prayer_times_instructions(lat, lng, method)

        base_prompt += "\n## Task Management\n" + \
            "You can create tasks for the user.\n\n" + \
            "Simple format: `[TASK: title]`\n" + \
            "Full format: `[ADD_TASK: title group=\"Group Name\" priority=high|medium|low due=\"YYYY-MM-DD\" description=\"Details\" recurrence=daily|weekly|monthly|yearly]`\n"

        user_notes = self.server.llm_args.get('user_notes', '')
        if user_notes and user_notes.strip():
            base_prompt = "## Personal Context\n" + user_notes.strip() + "\n\n" + base_prompt

        memories = load_memories_from_db(self.server.db_path)
        if memories:
            memories_block = "## What I Remember About You\n"
            for m in memories:
                memories_block += f"- {m}\n"
            base_prompt = memories_block + "\n" + base_prompt

        search_enabled = self.server.llm_args.get('search_enabled', 'true').lower() == 'true'
        if search_enabled:
            base_prompt += "\n\n" + \
                "5. Web Search:\n" + \
                "   Output: `[SEARCH: QUERY]`\n" + \
                "   When using search results, cite your sources with markdown links. Never invent URLs."

        messages = [{"role": "system", "content": base_prompt}] + history

        api_url = self.server.llm_args.get('api_url', "http://localhost:11434/v1")
        api_key = self.server.llm_args.get('api_key', "")
        model_name = self.server.llm_args.get('model', "llama3")

        if api_url.endswith('/'):
            api_url = api_url[:-1]
        endpoint = f"{api_url}/chat/completions"

        post_fields = {
            "model": model_name,
            "messages": messages,
            "stream": True,
            "temperature": 0.7
        }

        req = urllib.request.Request(endpoint, data=json.dumps(post_fields).encode('utf-8'))
        req.add_header('Content-Type', 'application/json')
        req.add_header('Connection', 'close')
        if api_key:
            req.add_header('Authorization', f'Bearer {api_key}')

        full_response = ""
        # Build opener that ignores system proxies for local loopback
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(req, timeout=300) as response:
            for line in response:
                if not line.strip():
                    continue
                line_str = line.decode('utf-8').strip()
                if line_str.startswith('data: '):
                    data_content = line_str[6:]
                    if data_content == '[DONE]':
                        break
                    content = ''
                    try:
                        chunk = json.loads(data_content)
                        delta = chunk.get('choices', [{}])[0].get('delta', {})
                        content = delta.get('content', '')
                        if content:
                            full_response += content
                    except Exception:
                        pass

                    if content:
                        try:
                            self.wfile.write(f"data: {json.dumps({'content': content})}\n\n".encode('utf-8'))
                            self.wfile.flush()
                        except (ConnectionError, BrokenPipeError, OSError):
                            logger.info("Client disconnected. Stopping stream.")
                            break
        return full_response

    def handle_get_tasks(self):
        conn = open_db_with_retry(self.server.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("""
            SELECT t.id, t.title, t.priority, t.due_date, (t.status = 'done') as completed, g.name as group_name
            FROM tasks t
            LEFT JOIN task_groups g ON t.group_id = g.id
            ORDER BY (t.status = 'done') ASC, t.priority DESC, t.created_at DESC
        """)
        rows = cursor.fetchall()
        tasks = [dict(r) for r in rows]
        conn.close()
        self._send_json(200, tasks)

    def handle_get_memories(self):
        conn = open_db_with_retry(self.server.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("SELECT id, content, created_at FROM memories ORDER BY created_at DESC")
        rows = cursor.fetchall()
        memories = [dict(r) for r in rows]
        conn.close()
        self._send_json(200, memories)

    def handle_tasks_toggle(self, data):
        task_id = validate_id(data.get('id'), "task_id")
        completed = data.get('completed', 0)
        if not task_id:
            self._send_error_json(400, "Missing or invalid task id")
            return

        conn = open_db_with_retry(self.server.db_path)
        cursor = conn.cursor()
        now = int(time.time() * 1000)
        status = 'done' if completed else 'pending'
        completed_at = now if completed else None
        cursor.execute("UPDATE tasks SET status = ?, completed_at = ? WHERE id = ?", (status, completed_at, task_id))
        conn.commit()
        conn.close()
        self._send_json(200, {"success": True})

    def handle_memories_delete(self, data):
        memory_id = validate_id(data.get('id'), "memory_id")
        if not memory_id:
            self._send_error_json(400, "Missing or invalid memory id")
            return

        conn = open_db_with_retry(self.server.db_path)
        cursor = conn.cursor()
        cursor.execute("DELETE FROM memories WHERE id = ?", (memory_id,))
        conn.commit()
        conn.close()
        self._send_json(200, {"success": True})

    def handle_commands_action(self, data):
        message_id = validate_id(data.get('message_id'), "message_id")
        action = validate_action(data.get('action'))
        if not message_id or not action:
            self._send_error_json(400, "Missing message_id or invalid action")
            return

        conn = open_db_with_retry(self.server.db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT content FROM messages WHERE id = ?", (message_id,))
        row = cursor.fetchone()

        if not row:
            conn.close()
            self._send_error_json(404, "Message not found")
            return

        content_str = row[0]
        try:
            parsed = json.loads(content_str)
        except Exception:
            parsed = {"command": content_str, "status": "pending", "output": ""}

        if "instruction" in parsed:
            inst = parsed.get("instruction", "")
            files = parsed.get("files", "")
            model = data.get("model") if data.get("model") is not None else parsed.get("model", "")
            parsed["model"] = model

            command = "opencode run " + shlex.quote(inst)
            if files:
                for f in files.split(','):
                    f = f.strip()
                    if f:
                        command += " -f " + shlex.quote(f)
            if model:
                command += " --model " + shlex.quote(model)

            session_id_file = "/tmp/kde_opencode_session_id"
            try:
                with open(session_id_file, 'r') as sf:
                    existing_session_id = sf.read().strip()
                    if existing_session_id:
                        command += " --session " + shlex.quote(existing_session_id)
            except FileNotFoundError:
                pass
        else:
            command = parsed.get("command", "")

        now = int(time.time() * 1000)

        if action == "decline":
            parsed["status"] = "declined"
            new_content = json.dumps(parsed)
            cursor.execute("UPDATE messages SET content = ?, timestamp = ? WHERE id = ?", (new_content, now, message_id))
            conn.commit()
            conn.close()
            self._send_json(200, {"success": True, "status": "declined"})
            return

        parsed["status"] = "running"
        new_content = json.dumps(parsed)
        cursor.execute("UPDATE messages SET content = ?, timestamp = ? WHERE id = ?", (new_content, now, message_id))
        conn.commit()

        try:
            cmd_timeout = 300 if "instruction" in parsed else 30
            result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=cmd_timeout)
            output = result.stdout
            if result.stderr:
                output += "\n--- STDERR ---\n" + result.stderr
            status = "completed" if result.returncode == 0 else "error"

            if "instruction" in parsed:
                session_match = re.search(r'ses_[0-9a-f]{24}', output)
                if session_match:
                    session_id_file = "/tmp/kde_opencode_session_id"
                    with open(session_id_file, 'w') as sf:
                        sf.write(session_match.group(0))
        except subprocess.TimeoutExpired:
            output = f"Command timed out after {cmd_timeout} seconds."
            status = "error"
        except Exception as e:
            output = f"Execution failed: {str(e)}"
            status = "error"

        now_end = int(time.time() * 1000)
        parsed["status"] = status
        parsed["output"] = output
        new_content = json.dumps(parsed)
        cursor.execute("UPDATE messages SET content = ?, timestamp = ? WHERE id = ?", (new_content, now_end, message_id))
        conn.commit()
        conn.close()

        self._send_json(200, {"success": True, "status": status, "output": output})

# ──────────────────────────────────────────────
# PID file management
# ──────────────────────────────────────────────

def write_pid_file():
    try:
        with open(PID_FILE, 'w') as f:
            f.write(str(os.getpid()))
    except Exception as e:
        logger.warning("Failed to write PID file: %s", e)

def remove_pid_file():
    try:
        if os.path.exists(PID_FILE):
            with open(PID_FILE, 'r') as f:
                pid = int(f.read().strip())
            if pid == os.getpid():
                os.remove(PID_FILE)
    except Exception:
        pass

def cleanup_stale_pid():
    try:
        if os.path.exists(PID_FILE):
            with open(PID_FILE, 'r') as f:
                pid = int(f.read().strip())
            try:
                os.kill(pid, 0)
                logger.warning("Another instance is already running (PID %d). Exiting.", pid)
                sys.exit(1)
            except ProcessLookupError:
                os.remove(PID_FILE)
                logger.info("Removed stale PID file for dead process %d", pid)
    except (ValueError, FileNotFoundError):
        pass

# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────

def main():
    logging.basicConfig(
        level=logging.INFO,
        format='[%(asctime)s] %(levelname)s: %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S',
        stream=sys.stderr
    )

    parser = argparse.ArgumentParser(description="KDE Assistant Webserver Daemon")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--token", type=str, required=True)
    parser.add_argument("--api-url", type=str, default="http://localhost:11434/v1")
    parser.add_argument("--api-key", type=str, default="")
    parser.add_argument("--model", type=str, default="llama3")
    parser.add_argument("--system-prompt", type=str, default="You are a helpful assistant.")
    parser.add_argument("--db", type=str, default=None)
    parser.add_argument("--static-dir", type=str, required=True)
    parser.add_argument("--search-enabled", type=str, default="true")
    parser.add_argument("--prayer-latitude", type=str, default="")
    parser.add_argument("--prayer-longitude", type=str, default="")
    parser.add_argument("--prayer-method", type=str, default="3")
    parser.add_argument("--user-notes", type=str, default="")
    parser.add_argument("--bind", type=str, default="127.0.0.1",
                        help="Address to bind to (default: 127.0.0.1). Use 0.0.0.0 to expose on LAN.")

    args = parser.parse_args()

    cleanup_stale_pid()

    db_path = find_sqlite_db(args.db)

    conn = open_db_with_retry(db_path)
    run_db_migrations(conn)
    conn.close()

    logger.info("Starting server on %s:%d...", args.bind, args.port)
    logger.info("Database path: %s", db_path)
    logger.info("Static directory: %s", args.static_dir)

    server = None
    for attempt in range(10):
        try:
            server = ThreadingHTTPServer((args.bind, args.port), WebServerHandler)
            break
        except OSError as e:
            logger.info("Port %d is in use, retrying in 1s (attempt %d/10)...", args.port, attempt + 1)
            time.sleep(1)
    if not server:
        logger.error("Failed to bind to port %d after 10 attempts.", args.port)
        sys.exit(1)

    server.token = args.token
    server.static_dir = os.path.abspath(args.static_dir)
    server.db_path = db_path
    server.active_requests = {}
    server.llm_args = {
        "api_url": args.api_url,
        "api_key": args.api_key,
        "model": args.model,
        "system_prompt": args.system_prompt,
        "search_enabled": args.search_enabled,
        "prayer_latitude": args.prayer_latitude,
        "prayer_longitude": args.prayer_longitude,
        "prayer_method": args.prayer_method,
        "user_notes": args.user_notes
    }

    write_pid_file()

    def shutdown_handler(signum, frame):
        logger.info("Received signal %d, shutting down...", signum)
        remove_pid_file()
        server.shutdown()

    signal.signal(signal.SIGTERM, shutdown_handler)
    signal.signal(signal.SIGINT, shutdown_handler)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        remove_pid_file()
        logger.info("Server stopped.")

if __name__ == '__main__':
    main()
