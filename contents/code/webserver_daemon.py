#!/usr/bin/env python3
import os
import sys
import json
import sqlite3
import argparse
import urllib.request
import urllib.parse
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
            
        if path == '/api/messages':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            self.handle_post_message(json.loads(post_data.decode('utf-8')))
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
            
        now = int(urllib.parse.time.time() * 1000)
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
            assistant_now = int(urllib.parse.time.time() * 1000)
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
