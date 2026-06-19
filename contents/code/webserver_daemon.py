#!/usr/bin/env python3
import os
import sys
import json
import sqlite3
import argparse
import urllib.request
import urllib.parse
import time
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

# Resolve DB file location
def find_sqlite_db(custom_path=None):
    if custom_path and os.path.exists(custom_path):
        return custom_path
    
    home = os.path.expanduser("~")
    search_dirs = [
        os.path.join(home, ".local/share/plasmashell/QML/OfflineStorage/Databases"),
        os.path.join(home, ".local/share/plasmawindowed/QML/OfflineStorage/Databases"),
        os.path.join(home, ".local/share/plasmoidviewer/QML/OfflineStorage/Databases"),
    ]
    
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
        conn = sqlite3.connect(self.server.db_path)
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
            
        conn = sqlite3.connect(self.server.db_path)
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
        conn = sqlite3.connect(self.server.db_path)
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
            
            # Save assistant message to DB
            conn = sqlite3.connect(self.server.db_path)
            cursor = conn.cursor()
            assistant_now = int(time.time() * 1000)
            assistant_msg_id = f"msg_assistant_{assistant_now}"
            cursor.execute("INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)",
                           (assistant_msg_id, session_id, "assistant", full_response, assistant_now))
            cursor.execute("UPDATE sessions SET updated_at = ? WHERE id = ?", (assistant_now, session_id))
            conn.commit()
            conn.close()
        except Exception as e:
            err_msg = f"Error: {str(e)}"
            self.wfile.write(f"data: {json.dumps({'error': err_msg})}\n\n".encode('utf-8'))

    def stream_llm(self, history):
        # Prepare payloads
        system_prompt = self.server.llm_args.get('system_prompt', "You are a helpful assistant.")
        messages = [{"role": "system", "content": system_prompt}] + history
        
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
        conn = sqlite3.connect(self.server.db_path)
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
        conn = sqlite3.connect(self.server.db_path)
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
        
        conn = sqlite3.connect(self.server.db_path)
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
        
        conn = sqlite3.connect(self.server.db_path)
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
        
        conn = sqlite3.connect(self.server.db_path)
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
            result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=30)
            output = result.stdout
            if result.stderr:
                output += "\n--- STDERR ---\n" + result.stderr
            status = "completed" if result.returncode == 0 else "error"
        except subprocess.TimeoutExpired:
            output = "Command timed out after 30 seconds."
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
    
    args = parser.parse_args()
    
    db_path = find_sqlite_db(args.db)
    print(f"Starting server on port {args.port}...")
    print(f"Database path: {db_path}")
    print(f"Static directory: {args.static_dir}")
    
    server = HTTPServer(('0.0.0.0', args.port), WebServerHandler)
    server.token = args.token
    server.static_dir = os.path.abspath(args.static_dir)
    server.db_path = db_path
    server.llm_args = {
        "api_url": args.api_url,
        "api_key": args.api_key,
        "model": args.model,
        "system_prompt": args.system_prompt
    }
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    print("Server stopped.")

if __name__ == '__main__':
    main()
