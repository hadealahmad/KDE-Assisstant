/*
 * KDE Assistant Mobile — app.js
 * Handles local auth, D-Bus session logic, REST calling, and Data-Driven Card Rendering (Path C)
 */

let activeToken = '';
let activeSessionId = '';
const chatFlow = document.getElementById('chat-flow');
const promptInput = document.getElementById('prompt-input');
const sessionTitle = document.getElementById('session-title');

// ── Auth & Setup ───────────────────────────────────────
function init() {
    // Check URL parameters for token
    const params = new URLSearchParams(window.location.search);
    let token = params.get('token');
    
    if (!token) {
        token = localStorage.getItem('web_access_token');
    }
    
    if (token) {
        activeToken = token;
        localStorage.setItem('web_access_token', token);
        loadSessions();
    } else {
        document.getElementById('auth-modal').style.display = 'flex';
    }
    
    setupEventListeners();
}

function setupEventListeners() {
    // Passcode Verification
    document.getElementById('auth-submit-btn').addEventListener('click', () => {
        const tokenInput = document.getElementById('passcode-input').value.trim();
        if (tokenInput.length === 6) {
            verifyToken(tokenInput);
        }
    });

    // New Chat
    document.getElementById('new-chat-btn').addEventListener('click', () => {
        startNewChat();
    });

    // Toggle Sidebar
    document.getElementById('menu-toggle-btn').addEventListener('click', () => {
        document.getElementById('sidebar').classList.toggle('open');
    });

    // Send Prompt
    document.getElementById('send-btn').addEventListener('click', () => {
        submitPrompt();
    });

    promptInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            submitPrompt();
        }
    });
}

async function verifyToken(token) {
    const errorMsg = document.getElementById('auth-error-msg');
    errorMsg.textContent = 'Verifying...';
    try {
        const response = await fetch(`/api/sessions?token=${token}`);
        if (response.status === 200) {
            activeToken = token;
            localStorage.setItem('web_access_token', token);
            document.getElementById('auth-modal').style.display = 'none';
            loadSessions();
        } else {
            errorMsg.textContent = 'Invalid Passcode. Please try again.';
        }
    } catch (e) {
        errorMsg.textContent = 'Connection error. Is the server running?';
    }
}

// ── Sessions & Messages ────────────────────────────────
async function loadSessions() {
    try {
        const response = await fetch(`/api/sessions?token=${activeToken}`);
        if (response.status === 401) {
            document.getElementById('auth-modal').style.display = 'flex';
            return;
        }
        const sessions = await response.json();
        const list = document.getElementById('sessions-list');
        list.innerHTML = '';
        
        sessions.forEach(sess => {
            const item = document.createElement('div');
            item.className = 'session-item';
            if (sess.id === activeSessionId) item.classList.add('active');
            item.textContent = sess.title || 'Untitled Session';
            item.addEventListener('click', () => {
                selectSession(sess.id, sess.title);
                document.getElementById('sidebar').classList.remove('open');
            });
            list.appendChild(item);
        });
    } catch (e) {
        console.error("Failed to load sessions:", e);
    }
}

function startNewChat() {
    activeSessionId = '';
    sessionTitle.textContent = 'New Chat';
    chatFlow.innerHTML = `
        <div class="empty-state">
            <div class="assistant-logo">🤖</div>
            <h3>KDE Assistant</h3>
            <p>Ask anything. Accessing your local desktop LLM model from your phone.</p>
        </div>
    `;
    // Update active state in list
    document.querySelectorAll('.session-item').forEach(item => item.classList.remove('active'));
}

async function selectSession(sessionId, title) {
    activeSessionId = sessionId;
    sessionTitle.textContent = title || 'Chat';
    chatFlow.innerHTML = '<div class="empty-state"><p>Loading messages...</p></div>';
    
    // Highlight sidebar active item
    document.querySelectorAll('.session-item').forEach(item => item.classList.remove('active'));
    
    try {
        const response = await fetch(`/api/messages?session_id=${sessionId}&token=${activeToken}`);
        const messages = await response.json();
        chatFlow.innerHTML = '';
        
        messages.forEach(msg => {
            appendMessageBubble(msg.role, msg.content);
        });
        
        scrollToBottom();
    } catch (e) {
        chatFlow.innerHTML = '<div class="empty-state"><p class="error">Failed to load chat history.</p></div>';
    }
}

// ── Rendering & Formatting (Path C) ───────────────────
function appendMessageBubble(role, content) {
    // Hide empty state if present
    const empty = chatFlow.querySelector('.empty-state');
    if (empty) empty.remove();
    
    const bubble = document.createElement('div');
    bubble.className = `message-bubble ${role}`;
    
    // Format message structure (Thinking Blocks, Tasks, Memories)
    let preprocessed = content;
    
    // 1. Thinking Block Extraction
    let thinkingText = '';
    const startTag = "<thinking>";
    const endTag = "</thinking>";
    const startIdx = content.indexOf(startTag);
    if (startIdx !== -1) {
        const endIdx = content.indexOf(endTag, startIdx + startTag.length);
        if (endIdx !== -1) {
            thinkingText = content.substring(startIdx + startTag.length, endIdx).trim();
            preprocessed = (content.substring(0, startIdx) + content.substring(endIdx + endTag.length)).trim();
        } else {
            thinkingText = content.substring(startIdx + startTag.length).trim();
            preprocessed = content.substring(0, startIdx).trim();
        }
    }
    
    if (thinkingText) {
        const thinkDiv = document.createElement('div');
        thinkDiv.className = 'thinking-block';
        thinkDiv.innerHTML = `<strong>Reasoning:</strong><br>${thinkingText}`;
        bubble.appendChild(thinkDiv);
    }
    
    // 2. Body Text Markdown render (simplified plain-text for basic browser display)
    const textSpan = document.createElement('span');
    textSpan.innerHTML = formatMarkdown(preprocessed);
    bubble.appendChild(textSpan);
    
    // 3. Task / Memory Card Rendering (Path C)
    if (content.includes('[add_task:') || content.includes('[task:')) {
        const taskCard = document.createElement('div');
        taskCard.className = 'card-wrapper task';
        
        // Parse Title shorthand
        let title = 'New Task';
        const taskMatch = content.match(/\[task:\s*([^\]]+)\]/i);
        const addTaskMatch = content.match(/\[add_task:\s*([^\]]+)\]/i);
        if (taskMatch) {
            title = taskMatch[1].trim();
        } else if (addTaskMatch) {
            title = addTaskMatch[1].split(/\s+(?:group|priority|due|description|recurrence)=/i)[0].trim();
        }
        
        taskCard.innerHTML = `<div class="card-header">✅ Task Created</div><div><strong>${title}</strong></div>`;
        bubble.appendChild(taskCard);
    }
    
    if (content.includes('[remember:')) {
        const memoryCard = document.createElement('div');
        memoryCard.className = 'card-wrapper memory';
        const memMatch = content.match(/\[remember:\s*([^\]]+)\]/i);
        const memContent = memMatch ? memMatch[1].trim() : 'Saved Fact';
        memoryCard.innerHTML = `<div class="card-header">🧠 Memory Saved</div><div><em>"${memContent}"</em></div>`;
        bubble.appendChild(memoryCard);
    }
    
    chatFlow.appendChild(bubble);
    return bubble;
}

function formatMarkdown(text) {
    if (!text) return "";
    return text
        .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") // sanitize
        .replace(/\n/g, '<br>')
        .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
        .replace(/\*([^*]+)\*/g, '<em>$1</em>')
        .replace(/`([^`]+)`/g, '<code>$1</code>');
}

// ── Submit Prompt & SSE Streaming ──────────────────────
async function submitPrompt() {
    const text = promptInput.value.trim();
    if (!text) return;
    
    promptInput.value = '';
    appendMessageBubble('user', text);
    scrollToBottom();
    
    // Append loading assistant bubble
    const assistantBubble = appendMessageBubble('assistant', '');
    const assistantSpan = assistantBubble.querySelector('span');
    assistantSpan.textContent = 'Generating...';
    
    try {
        const response = await fetch(`/api/messages?token=${activeToken}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                session_id: activeSessionId,
                prompt: text
            })
        });
        
        if (response.status !== 200) {
            assistantSpan.textContent = 'Error: Failed to connect to local LLM backend.';
            return;
        }
        
        assistantSpan.textContent = '';
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let partialLine = '';
        let fullContent = '';
        
        while (true) {
            const { value, done } = await reader.read();
            if (done) break;
            
            const chunk = decoder.decode(value, { stream: true });
            const lines = (partialLine + chunk).split('\n');
            partialLine = lines.pop();
            
            for (const line of lines) {
                const trimmed = line.trim();
                if (trimmed.startsWith('data: ')) {
                    try {
                        const data = JSON.parse(trimmed.substring(6));
                        if (data.content) {
                            fullContent += data.content;
                            
                            // Re-render contents dynamically to process tags/thinking on the fly
                            assistantBubble.innerHTML = '';
                            
                            // 1. Re-render thinking block
                            let cleanBody = fullContent;
                            let thinkingText = '';
                            const startTag = "<thinking>";
                            const endTag = "</thinking>";
                            const startIdx = fullContent.indexOf(startTag);
                            if (startIdx !== -1) {
                                const endIdx = fullContent.indexOf(endTag, startIdx + startTag.length);
                                if (endIdx !== -1) {
                                    thinkingText = fullContent.substring(startIdx + startTag.length, endIdx).trim();
                                    cleanBody = (fullContent.substring(0, startIdx) + fullContent.substring(endIdx + endTag.length)).trim();
                                } else {
                                    thinkingText = fullContent.substring(startIdx + startTag.length).trim();
                                    cleanBody = fullContent.substring(0, startIdx).trim();
                                }
                            }
                            
                            if (thinkingText) {
                                const thinkDiv = document.createElement('div');
                                thinkDiv.className = 'thinking-block';
                                thinkDiv.innerHTML = `<strong>Reasoning:</strong><br>${thinkingText}`;
                                assistantBubble.appendChild(thinkDiv);
                            }
                            
                            // 2. Re-render text span
                            const bodySpan = document.createElement('span');
                            bodySpan.innerHTML = formatMarkdown(cleanBody);
                            assistantBubble.appendChild(bodySpan);
                            
                            // 3. Render Cards if finalized (stream done)
                            if (fullContent.includes('[add_task:') || fullContent.includes('[task:')) {
                                const taskCard = document.createElement('div');
                                taskCard.className = 'card-wrapper task';
                                let title = 'New Task';
                                const taskMatch = fullContent.match(/\[task:\s*([^\]]+)\]/i);
                                if (taskMatch) title = taskMatch[1].trim();
                                taskCard.innerHTML = `<div class="card-header">✅ Task Created</div><div><strong>${title}</strong></div>`;
                                assistantBubble.appendChild(taskCard);
                            }
                            if (fullContent.includes('[remember:')) {
                                const memoryCard = document.createElement('div');
                                memoryCard.className = 'card-wrapper memory';
                                const memMatch = fullContent.match(/\[remember:\s*([^\]]+)\]/i);
                                const memContent = memMatch ? memMatch[1].trim() : 'Saved Fact';
                                memoryCard.innerHTML = `<div class="card-header">🧠 Memory Saved</div><div><em>"${memContent}"</em></div>`;
                                assistantBubble.appendChild(memoryCard);
                            }
                            
                            scrollToBottom();
                        } else if (data.error) {
                            assistantSpan.textContent = data.error;
                        }
                    } catch (e) {
                        // JSON parse error on incomplete chunks
                    }
                }
            }
        }
        
        // Reload sessions list to show updated title / order
        loadSessions();
    } catch (e) {
        assistantSpan.textContent = 'Network Error. Could not connect to local server.';
    }
}

function scrollToBottom() {
    chatFlow.scrollTop = chatFlow.scrollHeight;
}

// Start
init();
