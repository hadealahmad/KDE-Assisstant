#!/usr/bin/env python3
import os
import re
import sys
import json
import sqlite3
import argparse
import urllib.request
import urllib.parse
import time
import subprocess
import datetime
import shlex
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# Gregorian to Julian Day Number (JDN)
def gregorian_to_jdn(year, month, day):
    a = (14 - month) // 12
    y = year + 4800 - a
    m = month + 12 * a - 3
    return day + (153 * m + 2) // 5 + 365 * y + y // 4 - y // 100 + y // 400 - 32045

# Julian Day Number to Hijri date
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

def load_memories_from_db(db_path):
    memories = []
    try:
        conn = sqlite3.connect(db_path, timeout=30.0)
        cursor = conn.cursor()
        cursor.execute("SELECT content FROM memories ORDER BY created_at ASC")
        rows = cursor.fetchall()
        for r in rows:
            memories.append(r[0])
        conn.close()
    except Exception as e:
        pass
    return memories

# Parse commands from assistant response
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

# Resolve DB file location
def find_sqlite_db(custom_path=None):
    if custom_path and os.path.exists(custom_path):
        return custom_path
    
    home = os.path.expanduser("~")
    
    # Walk up parent processes to find the host process name
    host_name = None
    curr_pid = os.getpid()
    for _ in range(5):
        try:
            # Read PPid
            with open(f"/proc/{curr_pid}/status", "r") as f:
                ppid = None
                for line in f:
                    if line.startswith("PPid:"):
                        ppid = int(line.split()[1])
                        break
            if not ppid or ppid <= 1:
                break
                
            # Read cmdline of parent
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
            
    print(f"Detected QML host process: {host_name}")
    
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
            return path
            
    # Fallback recursive search
    for root, dirs, files in os.walk(os.path.join(home, ".local/share")):
        if db_filename in files:
            return os.path.join(root, db_filename)
            
    # Default to plasmashell databases dir
    default_dir = os.path.join(home, ".local/share/plasmashell/QML/OfflineStorage/Databases")
    os.makedirs(default_dir, exist_ok=True)
    return os.path.join(default_dir, db_filename)

class WebServerHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Silence default logs to clean stdout/stderr
        pass

    def check_auth(self):
        # Retrieve token from query params or Authorization header
        parsed_url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(parsed_url.query)
        token = query.get('token', [None])[0]
        
        if not token:
            auth_header = self.headers.get('Authorization')
            if auth_header and auth_header.startswith('Bearer '):
                token = auth_header[7:]
                
        if token == self.server.token:
            return True
            
        self.send_response(401)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"error": "Unauthorized"}).encode('utf-8'))
        return False

    def do_GET(self):
        parsed_url = urllib.parse.urlparse(self.path)
        path = parsed_url.path
        
        # API Routes
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
                self.send_error(404, "API endpoint not found")
            return

        # Static files serving
        if path == '/':
            path = '/index.html'
            
        # Clean path to prevent directory traversal vulnerabilities
        safe_path = os.path.normpath(path).lstrip('/')
        file_path = os.path.join(self.server.static_dir, safe_path)
        
        # Check if the file is inside static_dir
        if not file_path.startswith(self.server.static_dir) or not os.path.exists(file_path) or os.path.isdir(file_path):
            # Try serving from contents/code/ if we are looking for JS helpers
            if safe_path.startswith('code/') or safe_path.startswith('contents/code/'):
                base_dir = os.path.dirname(self.server.static_dir) # contents/
                code_path = os.path.join(base_dir, safe_path.replace('contents/', ''))
                if os.path.exists(code_path):
                    file_path = code_path
                else:
                    self.send_error(404, "File not found")
                    return
            else:
                self.send_error(404, "File not found")
                return

        # Determine MIME type
        mime = 'text/plain'
        if file_path.endswith('.html'):
            mime = 'text/html'
        elif file_path.endswith('.css'):
            mime = 'text/css'
        elif file_path.endswith('.js'):
            mime = 'application/javascript'
        elif file_path.endswith('.json'):
            mime = 'application/json'
        elif file_path.endswith('.png'):
            mime = 'image/png'

        self.send_response(200)
        self.send_header('Content-Type', mime)
        self.end_headers()
        with open(file_path, 'rb') as f:
            self.wfile.write(f.read())

    def do_POST(self):
        parsed_url = urllib.parse.urlparse(self.path)
        path = parsed_url.path
        
        if not self.check_auth():
            return
            
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length) if content_length > 0 else b'{}'
        try:
            data = json.loads(post_data.decode('utf-8'))
        except Exception:
            data = {}

        if path == '/api/messages':
            self.handle_post_message(data)
        elif path == '/api/tasks/toggle':
            self.handle_tasks_toggle(data)
        elif path == '/api/memories/delete':
            self.handle_memories_delete(data)
        elif path == '/api/commands/action':
            self.handle_commands_action(data)
        else:
            self.send_error(404, "API endpoint not found")

    def handle_get_sessions(self):
        conn = sqlite3.connect(self.server.db_path, timeout=30.0)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("SELECT id, title, created_at, updated_at FROM sessions ORDER BY updated_at DESC LIMIT 50")
        rows = cursor.fetchall()
        sessions = [dict(r) for r in rows]
        conn.close()
        
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(sessions).encode('utf-8'))

    def handle_get_messages(self, query_str):
        query = urllib.parse.parse_qs(query_str)
        session_id = query.get('session_id', [None])[0]
        if not session_id:
            self.send_error(400, "Missing session_id")
            return
            
        conn = sqlite3.connect(self.server.db_path, timeout=30.0)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("SELECT id, role, content, timestamp FROM messages WHERE session_id = ? ORDER BY timestamp ASC", (session_id,))
        rows = cursor.fetchall()
        messages = [dict(r) for r in rows]
        conn.close()
        
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(messages).encode('utf-8'))

    def handle_post_message(self, data):
        session_id = data.get('session_id')
        prompt = data.get('prompt')
        
        if not prompt:
            self.send_error(400, "Missing prompt")
            return
            
        now = int(time.time() * 1000)
        conn = sqlite3.connect(self.server.db_path, timeout=30.0)
        cursor = conn.cursor()
        
        # Create session if missing
        if not session_id:
            session_id = f"sess_{now}"
            cursor.execute("INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)",
                           (session_id, prompt[:25] + ("..." if len(prompt) > 25 else ""), now, now))
                           
        # Save user message
        user_msg_id = f"msg_user_{now}"
        cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                       (user_msg_id, session_id, "user", prompt, now))
        cursor.execute("UPDATE sessions SET updated_at = ? WHERE id = ?", (now, session_id))
        conn.commit()
        
        # Load chat history context
        cursor.execute("SELECT role, content FROM messages WHERE session_id = ? ORDER BY timestamp ASC", (session_id,))
        history = [{"role": r[0], "content": r[1]} for r in cursor.fetchall()]
        conn.close()

        # Send SSE Headers
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Cache-Control', 'no-cache')
        self.send_header('Connection', 'keep-alive')
        self.end_headers()

        # Stream LLM Response
        try:
            full_response = self.stream_llm(history)
            
            # Parse command tag
            cmd_tag = parse_command_tag(full_response)
            
            conn = sqlite3.connect(self.server.db_path, timeout=30.0)
            cursor = conn.cursor()
            assistant_now = int(time.time() * 1000)
            
            if cmd_tag:
                if cmd_tag["type"] == "remember":
                    mem_content = cmd_tag["content"]
                    clean_response = re.sub(r'\[remember:\s*[\s\S]+?\]', '', full_response, flags=re.IGNORECASE).strip()
                    if not clean_response:
                        clean_response = f"Got it! I will remember: \"{mem_content}\""
                        
                    mem_id = f"mem_{int(time.time() * 1000)}_{os.urandom(4).hex()}"
                    
                    try:
                        cursor.execute("INSERT INTO memories (id, content, created_at, source_session_id) VALUES (?, ?, ?, ?)",
                                       (mem_id, mem_content, assistant_now, session_id))
                        
                        memory_card_content = json.dumps({"id": mem_id, "content": mem_content})
                        cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                                       (f"msg_mem_{assistant_now}", session_id, "memory", memory_card_content, assistant_now))
                        
                        cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                                       (f"msg_assistant_{assistant_now}_text", session_id, "assistant", clean_response, assistant_now + 1))
                        
                        # Trigger system notification
                        subprocess.run(["notify-send", "-i", "dialog-information", "KDE Assistant", f"Memory Saved: {mem_content}"], capture_output=True)
                    except Exception as e:
                        cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                                       (f"msg_mem_{assistant_now}_err", session_id, "error", f"Failed to save memory: database error.", assistant_now))
                        # Trigger fail system notification
                        subprocess.run(["notify-send", "-i", "dialog-error", "KDE Assistant", "Failed to save memory."], capture_output=True)
                    
                elif cmd_tag["type"] in ("task", "add_task"):
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
                                group_id = f"group_{int(time.time() * 1000)}"
                                cursor.execute("INSERT INTO task_groups (id, name, created_at) VALUES (?, ?, ?)",
                                               (group_id, group_name, assistant_now))
                        
                        priority_val = 0
                        if priority_str == "high": priority_val = 3
                        elif priority_str == "medium": priority_val = 2
                        elif priority_str == "low": priority_val = 1
                        
                        due_date = None
                        if due_str:
                            try:
                                from datetime import datetime
                                dt = datetime.fromisoformat(due_str.replace('Z', '+00:00'))
                                due_date = int(dt.timestamp() * 1000)
                            except Exception:
                                pass
                        
                        task_id = f"task_{int(time.time() * 1000)}_{os.urandom(4).hex()}"
                        
                        cursor.execute("""
                            INSERT INTO tasks (id, group_id, title, description, status, priority, due_date, recurrence, created_at, source_session_id)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """, (task_id, group_id, task_title, description, 'pending', priority_val, due_date, recurrence, assistant_now, session_id))
                        
                        task_card_content = json.dumps({"id": task_id, "title": task_title})
                        cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                                       (f"msg_task_{assistant_now}", session_id, "task", task_card_content, assistant_now))
                        
                        cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                                       (f"msg_assistant_{assistant_now}_text", session_id, "assistant", clean_response, assistant_now + 1))
                        
                        # Trigger system notification
                        subprocess.run(["notify-send", "-i", "dialog-information", "KDE Assistant", f"Task Created: {task_title}"], capture_output=True)
                    except Exception as e:
                        cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                                       (f"msg_task_{assistant_now}_err", session_id, "error", f"Failed to create task: database error.", assistant_now))
                        # Trigger fail system notification
                        subprocess.run(["notify-send", "-i", "dialog-error", "KDE Assistant", "Failed to create task."], capture_output=True)
                                   
                elif cmd_tag["type"] == "system":
                    command = cmd_tag["command"]
                    clean_response = re.sub(r'\[system:\s*[\s\S]+?\]', '', full_response, flags=re.IGNORECASE).strip()
                    if not clean_response:
                        clean_response = f"Executing system command: `{command}`"
                        
                    command_card_content = json.dumps({"command": command, "output": "", "status": "pending"})
                    cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                                   (f"msg_cmd_{assistant_now}", session_id, "system_command", command_card_content, assistant_now))
                    
                    cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                                   (f"msg_assistant_{assistant_now}_text", session_id, "assistant", clean_response, assistant_now + 1))
                    
                elif cmd_tag["type"] == "grep":
                    pattern = cmd_tag["pattern"]
                    path = cmd_tag["path"]
                    clean_response = re.sub(r'\[grep:\s*[\s\S]+?\]', '', full_response, flags=re.IGNORECASE).strip()
                    if not clean_response:
                        clean_response = f"Searching for pattern: `{pattern}`"
                        
                    grep_cmd = f"rg -n --color=never {pattern} {path} || grep -rnI {pattern} {path}"
                    try:
                        result = subprocess.run(grep_cmd, shell=True, capture_output=True, text=True, timeout=15)
                        output = result.stdout
                        if result.stderr:
                            output += "\n" + result.stderr
                        status = "completed" if result.returncode == 0 else "error"
                    except Exception as e:
                        output = str(e)
                        status = "error"
                        
                    grep_card_content = json.dumps({"command": grep_cmd, "output": output, "status": status, "displayPattern": pattern})
                    cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                                   (f"msg_grep_{assistant_now}", session_id, "system_command", grep_card_content, assistant_now))
                    
                    cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                                   (f"msg_assistant_{assistant_now}_text", session_id, "assistant", clean_response, assistant_now + 1))
                    
                elif cmd_tag["type"] == "setting":
                    command = cmd_tag["command"]
                    description = cmd_tag["description"]
                    clean_response = re.sub(r'\[setting:\s*[\s\S]+?\]', '', full_response, flags=re.IGNORECASE).strip()
                    if not clean_response:
                        clean_response = f"Requested settings change: {description}"
                        
                    cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                                   (f"msg_setting_{assistant_now}", session_id, "setting_approval", f"{command}\n\n{description}", assistant_now))
                    
                    cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                                   (f"msg_assistant_{assistant_now}_text", session_id, "assistant", clean_response, assistant_now + 1))
                elif cmd_tag["type"] == "opencode":
                    instruction = cmd_tag["instruction"]
                    files = cmd_tag["files"]
                    model = cmd_tag["model"]
                    clean_response = re.sub(r'\[opencode:\s*[\s\S]+?\]', '', full_response, flags=re.IGNORECASE).strip()
                    if not clean_response:
                        clean_response = f"Requested OpenCode run: {instruction}"
                        
                    op_data = json.dumps({"instruction": instruction, "files": files, "model": model})
                    cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                                   (f"msg_opencode_{assistant_now}", session_id, "opencode_approval", op_data, assistant_now))
                    
                    cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                                   (f"msg_assistant_{assistant_now}_text", session_id, "assistant", clean_response, assistant_now + 1))
            else:
                cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                               (f"msg_assistant_{assistant_now}", session_id, "assistant", full_response, assistant_now))
                               
            cursor.execute("UPDATE sessions SET updated_at = ? WHERE id = ?", (assistant_now, session_id))
            conn.commit()
            conn.close()
        except Exception as e:
            err_msg = f"Error: {str(e)}"
            self.wfile.write(f"data: {json.dumps({'error': err_msg})}\n\n".encode('utf-8'))

    def stream_llm(self, history):
        # 1. Base system prompt
        base_prompt = self.server.llm_args.get('system_prompt', "You are a helpful assistant.")
        if not base_prompt or not base_prompt.strip():
            base_prompt = "You are a helpful assistant."
        base_prompt = base_prompt.strip()

        # 2. Date/Time context
        date_time_context = build_date_time_context()
        base_prompt = date_time_context + "\n\n" + base_prompt

        # 3. Add tools support instructions
        base_prompt += "\n\n" + \
            "CRITICAL INSTRUCTIONS FOR TOOL USAGE:\n" + \
            "You have access to local system integration tools. To run a tool, you must output a single command tag in brackets and STOP writing. Do not add any introduction, explanations, or concluding conversational text in the same turn.\n" + \
            "IMPORTANT: NEVER use bracketed placeholder symbols (like `<url>`, `<command>`, `<pattern>`, or `<path>`) literally. Replace them with real, concrete values.\n\n" + \
            "1. Webpage Content Fetching:\n" + \
            "   Use this to read the text of a URL.\n" + \
            "   Format: `[FETCH: URL]` (where URL is the actual address, e.g., `[FETCH: https://wiki.archlinux.org/title/KDE]`)\n" + \
            "   *Do not write `[FETCH: <url>]`.*\n\n" + \
            "2. Local File Search:\n" + \
            "   Use this to search for text patterns inside configuration files or directories.\n" + \
            "   Format: `[GREP: \"pattern\" \"path\"]` (both arguments must be inside double quotes, e.g., `[GREP: \"font\" \"~/.config/kdeglobals\"]`)\n" + \
            "   *Do not write `[GREP: <pattern> <path>]`.*\n\n" + \
            "3. Read-Only System Info & Directory Listing:\n" + \
            "   Use this to execute read-only CLI tools to inspect files, search directories, or check system status.\n" + \
            "   Format: `[SYSTEM: COMMAND]` (where COMMAND is the actual terminal command)\n" + \
            "   Approved commands: ls, find, cat, free -h, uname -a, df -h, uptime, lscpu, lsusb, lspci, ps aux, systemctl status <service>, pactl list, qdbus, dmesg | tail\n" + \
            "   Examples: `[SYSTEM: ls -la /run/media/hadi/SSD2]`, `[SYSTEM: ls -la \"/run/media/hadi/SSD2/Coding/KDE Assisstant/\"]` (always enclose paths containing spaces in double quotes!), `[SYSTEM: free -h]`, `[SYSTEM: cat ~/.config/kdeglobals]`\n" + \
            "   *Do not write `[SYSTEM: <command>]`.*\n\n" + \
            "4. Modifying KDE Settings / Configuration Changes:\n" + \
            "   Use this to request system settings changes (e.g. using `kwriteconfig6`). This displays an interactive card for user approval.\n" + \
            "   Format: `[SETTING: COMMAND description=\"DESCRIPTION\"]` (where COMMAND is the setting shell command, and DESCRIPTION is a brief explanation of what will change, in double quotes)\n" + \
            "   Example: `[SETTING: kwriteconfig6 --file kdeglobals --group General --key font \"Inter,10,-1,5,50,0,0,0,0,0\" description=\"Set General system font to Inter 10\"]`\n\n" + \
            "5. File Manager & Clickable Local Links:\n" + \
            "   When referencing local files or folders, always format them as clickable Markdown links using the `file://` protocol. The UI intercepts these links and opens them in the Dolphin File Manager when the user clicks them.\n" + \
            "   Format: `[Link Text](file://Absolute/Path)` (Note: use 3 slashes for absolute paths, e.g., `file:///run/media/...`)\n" + \
            "   Examples: `[Open Personal Folder](file:///run/media/hadi/NVME2/Personal)`, `[View config file](file:///home/hadi/.config/kdeglobals)`\n\n" + \
            "6. Saving a Memory:\n" + \
            "   Use this when the user shares something important they want you to remember across future conversations (preferences, facts about themselves, project details, etc.).\n" + \
            "   Format: `[REMEMBER: fact to remember]`\n" + \
            "   Example: `[REMEMBER: User prefers Python over JavaScript]`, `[REMEMBER: Main project is located at /run/media/hadi/SSD2/Coding/KDE Assisstant]`\n" + \
            "   *Only use this when the user explicitly asks you to remember something, or when they share clearly persistent personal information. Do not overuse it.*\n\n" + \
            "7. OpenCode Autonomous Coding Agent:\n" + \
            "   Use this to request autonomous code refactoring, review, or implementation in the local workspace. OpenCode will run in the background and can modify or create files. Delegate complex coding tasks to OpenCode instead of trying to explain or write code snippets manually.\n" + \
            "   Format: `[opencode: instruction files=\"file1,file2\" model=\"model_name\"]` (files and model are optional parameters, files must be a comma-separated list of relative or absolute paths)\n" + \
            "   Examples: `[opencode: Add retry logic to API calls and update tests files=\"contents/code/ApiClient.js,contents/code/StreamingManager.js\"]`, `[opencode: Review this config for security issues files=\"contents/config/main.xml\"]`"

        # 4. Inject prayer times instructions
        lat = self.server.llm_args.get('prayer_latitude', '')
        lng = self.server.llm_args.get('prayer_longitude', '')
        method = self.server.llm_args.get('prayer_method', '3')
        base_prompt += build_prayer_times_instructions(lat, lng, method)

        # 5. Inject task management instructions
        base_prompt += "\n## Task Management\n" + \
            "You can create tasks for the user. Use the task tool tags to save tasks to their task list.\n\n" + \
            "Simple format: `[TASK: title]`\n" + \
            "Full format: `[ADD_TASK: title group=\"Group Name\" priority=high|medium|low due=\"YYYY-MM-DD\" description=\"Details\" recurrence=daily|weekly|monthly|yearly]`\n\n" + \
            "Examples:\n" + \
            "  `[TASK: Buy groceries]`\n" + \
            "  `[ADD_TASK: Review PR #42 group=\"Work\" priority=high due=\"2026-06-20\" description=\"Check security and tests\"]`\n" + \
            "  `[ADD_TASK: Weekly team sync group=\"Work\" recurrence=weekly]`\n\n" + \
            "When the user asks you to create multiple tasks, you can output multiple task tags in a single response. " + \
            "Group related tasks together by using the same group name — the system will reuse existing groups automatically.\n" + \
            "Multiple task example:\n" + \
            "  `[ADD_TASK: Buy groceries group=\"Shopping\" priority=medium]\n  [ADD_TASK: Buy cleaning supplies group=\"Shopping\" priority=low]\n  [ADD_TASK: Call dentist group=\"Personal\" priority=high]`\n\n" + \
            "When the user asks you to create a task, track something, set a reminder, or mentions something they need to do, use this tool.\n" + \
            "If the user doesn't specify a group, you can omit it. If they don't specify priority, omit it.\n" + \
            "You can also suggest tasks when appropriate — for example, if the user mentions a deadline or something they need to remember to do."

        # 6. Inject user notes (if any)
        user_notes = self.server.llm_args.get('user_notes', '')
        if user_notes and user_notes.strip():
            base_prompt = "## Personal Context\n" + user_notes.strip() + "\n\n" + base_prompt

        # 7. Inject memories from DB
        memories = load_memories_from_db(self.server.db_path)
        if memories:
            memories_block = "## What I Remember About You\n"
            for m in memories:
                memories_block += f"- {m}\n"
            base_prompt = memories_block + "\n" + base_prompt

        # 8. Web Search (if enabled)
        search_enabled = self.server.llm_args.get('search_enabled', 'true').lower() == 'true'
        if search_enabled:
            base_prompt += "\n\n" + \
                "5. Web Search:\n" + \
                "   If you need to search the web, output: `[SEARCH: QUERY]` (e.g., `[SEARCH: how to change KDE font size command line]`). Only output the search command and wait for results.\n" + \
                "   *Do not write `[SEARCH: <query>]`.*\n" + \
                "   When using search results, cite your sources with direct markdown links using exact URLs from the search results (e.g., `[KDE Forum](url)`). Never invent URLs."

        messages = [{"role": "system", "content": base_prompt}] + history
        
        api_url = self.server.llm_args.get('api_url', "http://localhost:11434/v1")
        api_key = self.server.llm_args.get('api_key', "")
        model_name = self.server.llm_args.get('model', "llama3")
        
        # Clean and construct completions endpoint
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
        if api_key:
            req.add_header('Authorization', f'Bearer {api_key}')
            
        full_response = ""
        with urllib.request.urlopen(req) as response:
            for line in response:
                if not line.strip():
                    continue
                line_str = line.decode('utf-8').strip()
                if line_str.startswith('data: '):
                    data_content = line_str[6:]
                    if data_content == '[DONE]':
                        break
                    try:
                        chunk = json.loads(data_content)
                        delta = chunk.get('choices', [{}])[0].get('delta', {})
                        content = delta.get('content', '')
                        if content:
                            full_response += content
                            # Proxy to Web client
                            self.wfile.write(f"data: {json.dumps({'content': content})}\n\n".encode('utf-8'))
                            self.wfile.flush()
                    except Exception as e:
                        pass
        return full_response

    def handle_get_tasks(self):
        conn = sqlite3.connect(self.server.db_path, timeout=30.0)
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
        
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(tasks).encode('utf-8'))

    def handle_get_memories(self):
        conn = sqlite3.connect(self.server.db_path, timeout=30.0)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute("SELECT id, content, created_at FROM memories ORDER BY created_at DESC")
        rows = cursor.fetchall()
        memories = [dict(r) for r in rows]
        conn.close()
        
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(memories).encode('utf-8'))

    def handle_tasks_toggle(self, data):
        task_id = data.get('id')
        completed = data.get('completed', 0)
        if not task_id:
            self.send_error(400, "Missing task id")
            return
        
        conn = sqlite3.connect(self.server.db_path, timeout=30.0)
        cursor = conn.cursor()
        now = int(time.time() * 1000)
        status = 'done' if completed else 'pending'
        completed_at = now if completed else None
        cursor.execute("UPDATE tasks SET status = ?, completed_at = ? WHERE id = ?", (status, completed_at, task_id))
        conn.commit()
        conn.close()
        
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"success": True}).encode('utf-8'))

    def handle_memories_delete(self, data):
        memory_id = data.get('id')
        if not memory_id:
            self.send_error(400, "Missing memory id")
            return
        
        conn = sqlite3.connect(self.server.db_path, timeout=30.0)
        cursor = conn.cursor()
        cursor.execute("DELETE FROM memories WHERE id = ?", (memory_id,))
        conn.commit()
        conn.close()
        
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"success": True}).encode('utf-8'))

    def handle_commands_action(self, data):
        message_id = data.get('message_id')
        action = data.get('action')
        if not message_id or not action:
            self.send_error(400, "Missing message_id or action")
            return
        
        conn = sqlite3.connect(self.server.db_path, timeout=30.0)
        cursor = conn.cursor()
        cursor.execute("SELECT content FROM messages WHERE id = ?", (message_id,))
        row = cursor.fetchone()
        
        if not row:
            conn.close()
            self.send_error(404, "Message not found")
            return
            
        content_str = row[0]
        try:
            parsed = json.loads(content_str)
        except Exception:
            parsed = {"command": content_str, "status": "pending", "output": ""}
            
        if "instruction" in parsed:
            inst = parsed.get("instruction", "")
            files = parsed.get("files", "")
            # Read client overridden model if present, otherwise fallback to parsed model
            model = data.get("model") if data.get("model") is not None else parsed.get("model", "")
            parsed["model"] = model
            
            command = "opencode run " + shlex.quote(inst) + " --dangerously-skip-permissions"
            if files:
                for f in files.split(','):
                    f = f.strip()
                    if f:
                        command += " -f " + shlex.quote(f)
            if model:
                command += " --model " + shlex.quote(model)
        else:
            command = parsed.get("command", "")
        now = int(time.time() * 1000)
        
        if action == "decline":
            parsed["status"] = "declined"
            new_content = json.dumps(parsed)
            cursor.execute("UPDATE messages SET content = ?, timestamp = ? WHERE id = ?", (new_content, now, message_id))
            conn.commit()
            conn.close()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"success": True, "status": "declined"}).encode('utf-8'))
            return
            
        # Action is approve
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
        
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"success": True, "status": status, "output": output}).encode('utf-8'))

def main():
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
    
    args = parser.parse_args()
    
    db_path = find_sqlite_db(args.db)
    print(f"Starting server on port {args.port}...")
    print(f"Database path: {db_path}")
    print(f"Static directory: {args.static_dir}")
    
    server = ThreadingHTTPServer(('0.0.0.0', args.port), WebServerHandler)
    server.token = args.token
    server.static_dir = os.path.abspath(args.static_dir)
    server.db_path = db_path
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
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    print("Server stopped.")

if __name__ == '__main__':
    main()
