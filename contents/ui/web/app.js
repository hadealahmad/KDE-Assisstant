/*
 * KDE Assistant Mobile — app.js
 * Handles local authentication, D-Bus sessions, tabbed views (Chats, Tasks, Memories),
 * markdown parsing, collapsed reasoning, and interactive remote tool approvals (Path C).
 */

let activeToken = '';
let activeSessionId = '';
let recentSessions = []; // Global variable to store active sessions
let currentTab = 'sessions'; // sessions, tasks, memories
const chatFlow = document.getElementById('chat-flow');
const promptInput = document.getElementById('prompt-input');
const sessionTitle = document.getElementById('session-title');

// ── Init & Setup ──────────────────────────────────────────
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
    setupTabSwitching();
}

function setupEventListeners() {
    // Passcode Verification Modal
    document.getElementById('auth-submit-btn').addEventListener('click', () => {
        const tokenInput = document.getElementById('passcode-input').value.trim();
        if (tokenInput.length === 6) {
            verifyToken(tokenInput);
        }
    });

    // New Chat buttons
    document.getElementById('new-chat-btn').addEventListener('click', () => {
        startNewChat();
    });
    
    document.getElementById('header-new-chat-btn').addEventListener('click', () => {
        startNewChat();
    });

    // Close Sidebar button
    document.getElementById('close-sidebar-btn').addEventListener('click', () => {
        document.getElementById('sidebar').classList.remove('open');
    });

    // Toggle Sidebar Drawer (Mobile)
    document.getElementById('menu-toggle-btn').addEventListener('click', () => {
        document.getElementById('sidebar').classList.toggle('open');
    });

    // Send Button
    document.getElementById('send-btn').addEventListener('click', () => {
        submitPrompt();
    });

    // Enter Key Send (Shift+Enter for newline)
    promptInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            submitPrompt();
        }
    });

    // Auto-expand textarea on typing
    promptInput.addEventListener('input', function() {
        this.style.height = 'auto';
        this.style.height = (this.scrollHeight - 4) + 'px';
    });
}

async function verifyToken(token) {
    const errorMsg = document.getElementById('auth-error-msg');
    errorMsg.textContent = 'Verifying passcode...';
    try {
        const response = await fetch(`/api/sessions?token=${token}`);
        if (response.status === 200) {
            activeToken = token;
            localStorage.setItem('web_access_token', token);
            document.getElementById('auth-modal').style.display = 'none';
            loadSessions();
        } else {
            errorMsg.textContent = 'Invalid passcode. Check your computer settings.';
        }
    } catch (e) {
        errorMsg.textContent = 'Connection refused. Is the server running?';
    }
}

// ── Tab Switching Logic ────────────────────────────────────
function setupTabSwitching() {
    document.querySelectorAll('.tab-btn').forEach(btn => {
        btn.addEventListener('click', function() {
            const tabName = this.getAttribute('data-tab');
            if (tabName === currentTab) return;

            // Update Tab Button Active States
            document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
            this.classList.add('active');

            // Update Tab Panel Active States
            document.querySelectorAll('.tab-content-panel').forEach(panel => panel.classList.remove('active'));
            document.getElementById(`${tabName}-list`).classList.add('active');

            currentTab = tabName;
            
            // Load corresponding tab data
            if (tabName === 'sessions') {
                loadSessions();
            } else if (tabName === 'tasks') {
                loadTasks();
            } else if (tabName === 'memories') {
                loadMemories();
            }
        });
    });
}

// ── Data Loading & Fetching ────────────────────────────────
async function loadSessions() {
    try {
        const response = await fetch(`/api/sessions?token=${activeToken}`);
        if (response.status === 401) {
            document.getElementById('auth-modal').style.display = 'flex';
            return;
        }
        const sessions = await response.json();
        recentSessions = sessions; // Store sessions globally
        
        // If we are currently in an empty state (no activeSessionId), refresh the empty state to show latest links
        if (!activeSessionId) {
            startNewChat();
        }

        const list = document.getElementById('sessions-list');
        list.innerHTML = '';
        
        if (sessions.length === 0) {
            list.innerHTML = '<div style="color: var(--muted-foreground); text-align: center; padding: 20px; font-size: 0.8rem;">No chat history</div>';
            return;
        }

        sessions.forEach(sess => {
            const item = document.createElement('div');
            item.className = 'session-item';
            if (sess.id === activeSessionId) item.classList.add('active');
            item.textContent = sess.title || 'Untitled Chat';
            item.setAttribute('dir', 'auto');
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

async function loadTasks() {
    const list = document.getElementById('tasks-list');
    list.innerHTML = '<div style="color: var(--muted-foreground); text-align: center; padding: 20px; font-size: 0.8rem;">Loading tasks...</div>';
    
    try {
        const response = await fetch(`/api/tasks?token=${activeToken}`);
        if (response.status === 401) return;
        const tasks = await response.json();
        list.innerHTML = '';

        if (tasks.length === 0) {
            list.innerHTML = '<div style="color: var(--muted-foreground); text-align: center; padding: 20px; font-size: 0.8rem;">No tasks found</div>';
            return;
        }

        tasks.forEach(task => {
            const card = document.createElement('div');
            card.className = `task-item-card ${task.completed ? 'completed' : ''}`;
            
            // Generate Priority Badge Class
            const priorityClass = task.priority > 0 ? `priority-${task.priority}` : '';
            const priorityText = task.priority === 3 ? 'High' : task.priority === 2 ? 'Medium' : 'Low';
            
            // Format Due Date
            let dueDateText = '';
            if (task.due_date) {
                const date = new Date(parseInt(task.due_date));
                dueDateText = date.toLocaleDateString(undefined, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
            }

            card.innerHTML = `
                <label class="task-checkbox-container">
                    <input type="checkbox" ${task.completed ? 'checked' : ''} onchange="toggleTask('${task.id}', this.checked)">
                    <span class="task-checkbox"></span>
                </label>
                <div class="task-content">
                    <div class="task-title-text" dir="auto">${escapeHtml(task.title)}</div>
                    <div class="task-meta-row">
                        ${task.group_name ? `<span class="task-tag">${escapeHtml(task.group_name)}</span>` : ''}
                        ${task.priority > 0 ? `<span class="task-tag task-priority-tag ${priorityClass}">${priorityText}</span>` : ''}
                        ${dueDateText ? `<span class="task-tag" style="border-color: rgba(255,255,255,0.05); color:#71717a">📅 ${dueDateText}</span>` : ''}
                    </div>
                </div>
            `;
            list.appendChild(card);
        });
    } catch (e) {
        list.innerHTML = '<div class="error-text" style="text-align: center; padding: 20px;">Connection error loading tasks</div>';
    }
}

async function toggleTask(taskId, completed) {
    try {
        const response = await fetch(`/api/tasks/toggle?token=${activeToken}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ id: taskId, completed: completed ? 1 : 0 })
        });
        if (response.ok) {
            loadTasks();
            // Refresh main chat if needed
            if (activeSessionId) {
                reloadMessages();
            }
        }
    } catch (e) {
        console.error("Failed to toggle task status:", e);
    }
}

async function loadMemories() {
    const list = document.getElementById('memories-list');
    list.innerHTML = '<div style="color: var(--muted-foreground); text-align: center; padding: 20px; font-size: 0.8rem;">Loading memories...</div>';
    
    try {
        const response = await fetch(`/api/memories?token=${activeToken}`);
        if (response.status === 401) return;
        const memories = await response.json();
        list.innerHTML = '';

        if (memories.length === 0) {
            list.innerHTML = '<div style="color: var(--muted-foreground); text-align: center; padding: 20px; font-size: 0.8rem;">No memories saved yet</div>';
            return;
        }

        memories.forEach(mem => {
            const card = document.createElement('div');
            card.className = 'memory-item-card';
            card.innerHTML = `
                <div class="memory-text" dir="auto">"${escapeHtml(mem.content)}"</div>
                <button class="memory-delete-btn" onclick="deleteMemory('${mem.id}')" title="Delete Memory">
                    <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>
                </button>
            `;
            list.appendChild(card);
        });
    } catch (e) {
        list.innerHTML = '<div class="error-text" style="text-align: center; padding: 20px;">Connection error loading memories</div>';
    }
}

async function deleteMemory(memoryId) {
    if (!confirm("Are you sure you want to delete this memory?")) return;
    try {
        const response = await fetch(`/api/memories/delete?token=${activeToken}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ id: memoryId })
        });
        if (response.ok) {
            loadMemories();
            // Refresh main chat
            if (activeSessionId) {
                reloadMessages();
            }
        }
    } catch (e) {
        console.error("Failed to delete memory:", e);
    }
}

function startNewChat() {
    activeSessionId = '';
    sessionTitle.textContent = 'New Chat';
    
    let recentLinksHtml = '';
    if (recentSessions && recentSessions.length > 0) {
        const latestThree = recentSessions.slice(0, 3);
        recentLinksHtml = `
            <div class="recent-chats-container" style="margin-top: 24px; width: 100%; text-align: left;">
                <h4 style="font-size: 0.8rem; font-weight: 600; text-transform: uppercase; color: var(--muted-foreground); margin-bottom: 8px; letter-spacing: 0.05em;">Recent Chats</h4>
                <div class="recent-chats-links" style="display: flex; flex-direction: column; gap: 8px;">
                    ${latestThree.map(sess => `
                        <a href="#" class="recent-chat-link" onclick="event.preventDefault(); selectSession('${sess.id}', '${sess.title.replace(/'/g, "\\'")}')" style="display: flex; align-items: center; gap: 8px; padding: 10px 12px; background-color: var(--secondary); border: 1px solid var(--border); border-radius: var(--radius); color: var(--foreground); text-decoration: none; font-size: 0.88rem; transition: var(--transition);">
                            <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="color: var(--muted-foreground);"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
                            <span style="overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${escapeHtml(sess.title) || 'Untitled Chat'}</span>
                        </a>
                    `).join('')}
                </div>
            </div>
        `;
    }

    chatFlow.innerHTML = `
        <div class="empty-state">
            <div class="assistant-logo-container">
                <svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 8V4H8"/><rect width="16" height="12" x="4" y="8" rx="2"/><path d="M2 14h2"/><path d="M20 14h2"/><path d="M15 13v2"/><path d="M9 13v2"/></svg>
            </div>
            <h3>KDE Assistant Mobile Portal</h3>
            <p>Interact with your local LLM model and desktop tools. Your commands can be monitored and approved here.</p>
            ${recentLinksHtml}
        </div>
    `;
    document.querySelectorAll('.session-item').forEach(item => item.classList.remove('active'));
}

async function selectSession(sessionId, title) {
    activeSessionId = sessionId;
    sessionTitle.textContent = title || 'Chat';
    chatFlow.innerHTML = '<div class="empty-state"><p>Loading messages...</p></div>';
    
    // Highlight sidebar active item
    document.querySelectorAll('.session-item').forEach(item => {
        if (item.textContent === title) item.classList.add('active');
        else item.classList.remove('active');
    });
    
    await reloadMessages();
}

async function reloadMessages() {
    if (!activeSessionId) return;
    try {
        const response = await fetch(`/api/messages?session_id=${activeSessionId}&token=${activeToken}`);
        const messages = await response.json();
        chatFlow.innerHTML = '';
        
        messages.forEach(msg => {
            appendMessageBubble(msg);
        });
        
        scrollToBottom();
    } catch (e) {
        chatFlow.innerHTML = '<div class="empty-state"><p class="error-text">Failed to load chat history.</p></div>';
    }
}

// ── Custom Markdown Parser ──────────────────────────────────
function renderTable(rows, alignments) {
    if (rows.length === 0) return "";
    
    let html = '<div class="table-container"><table>';
    
    const parseRow = (rowStr) => {
        let clean = rowStr.trim();
        if (clean.startsWith('|')) clean = clean.slice(1);
        if (clean.endsWith('|')) clean = clean.slice(0, -1);
        return clean.split('|');
    };
    
    let headerCols = parseRow(rows[0]);
    html += '<thead><tr>';
    headerCols.forEach((col, idx) => {
        let align = alignments[idx] ? ` style="text-align: ${alignments[idx]}"` : '';
        html += `<th${align}>${col.trim()}</th>`;
    });
    html += '</tr></thead>';
    
    if (rows.length > 1) {
        html += '<tbody>';
        for (let r = 1; r < rows.length; r++) {
            let cols = parseRow(rows[r]);
            html += '<tr>';
            for (let idx = 0; idx < headerCols.length; idx++) {
                let col = cols[idx] || "";
                let align = alignments[idx] ? ` style="text-align: ${alignments[idx]}"` : '';
                html += `<td${align}>${col.trim()}</td>`;
            }
            html += '</tr>';
        }
        html += '</tbody>';
    }
    
    html += '</table></div>';
    return html;
}

function parseMarkdown(text) {
    if (!text) return "";
    
    let processed = text;
    const codeBlocks = [];
    
    // 1. Temporarily extract fenced code blocks to prevent inner markdown processing
    const codeBlockRegex = /```(\w*)\n([\s\S]*?)```/g;
    processed = processed.replace(codeBlockRegex, (match, lang, code) => {
        const placeholder = `__CODE_BLOCK_PLACEHOLDER_${codeBlocks.length}__`;
        codeBlocks.push({ lang: lang || 'code', code: code.trim() });
        return placeholder;
    });
    
    // 2. Sanitize HTML tags to prevent XSS
    processed = processed
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;");
        
    // 2.5 Parse Markdown Tables
    let lines = processed.split('\n');
    let inTable = false;
    let tableRows = [];
    let tableAlignments = [];
    let newLines = [];
    
    for (let i = 0; i < lines.length; i++) {
        let line = lines[i].trim();
        let isRow = line.includes('|');
        
        if (isRow) {
            if (!inTable) {
                let nextLine = (i + 1 < lines.length) ? lines[i + 1].trim() : '';
                let isSep = nextLine.includes('|') && /^[|:\s-]+$/.test(nextLine) && nextLine.includes('-');
                if (isSep) {
                    inTable = true;
                    tableRows = [line];
                    let cleanSep = nextLine.startsWith('|') ? nextLine.slice(1) : nextLine;
                    if (cleanSep.endsWith('|')) cleanSep = cleanSep.slice(0, -1);
                    let cols = cleanSep.split('|');
                    tableAlignments = cols.map(c => {
                        c = c.trim();
                        if (c.startsWith(':') && c.endsWith(':')) return 'center';
                        if (c.startsWith(':')) return 'left';
                        if (c.endsWith(':')) return 'right';
                        return '';
                    });
                    i++;
                    continue;
                } else {
                    newLines.push(lines[i]);
                }
            } else {
                tableRows.push(line);
            }
        } else {
            if (inTable) {
                newLines.push(renderTable(tableRows, tableAlignments));
                inTable = false;
                tableRows = [];
                tableAlignments = [];
            }
            newLines.push(lines[i]);
        }
    }
    if (inTable) {
        newLines.push(renderTable(tableRows, tableAlignments));
    }
    processed = newLines.join('\n');
        
    // 3. Headers
    processed = processed.replace(/^### (.*$)/gim, '<h3>$1</h3>');
    processed = processed.replace(/^## (.*$)/gim, '<h2>$1</h2>');
    processed = processed.replace(/^# (.*$)/gim, '<h1>$1</h1>');
    
    // 4. Blockquotes
    processed = processed.replace(/^\> (.*$)/gim, '<blockquote>$1</blockquote>');
    
    // 5. Bold & Italic
    processed = processed.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
    processed = processed.replace(/\*([^*]+)\*/g, '<em>$1</em>');
    processed = processed.replace(/_([^_]+)_/g, '<em>$1</em>');
    
    // 6. Inline code
    processed = processed.replace(/`([^`]+)`/g, '<code>$1</code>');
    
    // 7. Bullet Lists
    processed = processed.replace(/^\s*[-*]\s+(.*$)/gim, '<li>$1</li>');
    processed = processed.replace(/((?:<li>.*<\/li>)+)/gim, '<ul>$1</ul>');
    processed = processed.replace(/<\/ul>\s*<ul>/g, ''); // merge adjacent
    
    // 8. Numbered Lists
    processed = processed.replace(/^\s*\d+\.\s+(.*$)/gim, '<li class="ol-item">$1</li>');
    processed = processed.replace(/((?:<li class="ol-item">.*<\/li>)+)/gim, '<ol>$1</ol>');
    processed = processed.replace(/class="ol-item"/g, '');
    processed = processed.replace(/<\/ol>\s*<ol>/g, ''); // merge adjacent
    
    // 9. Line breaks
    processed = processed.replace(/\n\n/g, '<br><br>');
    processed = processed.replace(/\n/g, '<br>');
    
    // 10. Restore code blocks with styled containers and copy button
    codeBlocks.forEach((block, index) => {
        const placeholder = `__CODE_BLOCK_PLACEHOLDER_${index}__`;
        const escapedCode = block.code
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;");
            
        const blockHtml = `
            <div class="code-block-container">
                <div class="code-block-header">
                    <span class="code-block-lang">${block.lang}</span>
                    <button class="copy-code-btn" onclick="copyToClipboard(this)">Copy</button>
                </div>
                <pre><code>${escapedCode}</code></pre>
            </div>
        `;
        processed = processed.replace(placeholder, blockHtml);
    });
    
    return processed;
}

// Global helper for copying code blocks
window.copyToClipboard = function(btn) {
    const pre = btn.closest('.code-block-container').querySelector('pre');
    const text = pre.textContent;
    navigator.clipboard.writeText(text).then(() => {
        btn.textContent = 'Copied!';
        btn.style.color = '#34d399'; // Green text
        setTimeout(() => {
            btn.textContent = 'Copy';
            btn.style.color = '';
        }, 2000);
    });
};

// ── Rendering & Formatting (Path C) ──────────────────────────
function appendMessageBubble(msg) {
    const empty = chatFlow.querySelector('.empty-state');
    if (empty) empty.remove();
    
    const container = document.createElement('div');
    const role = msg.role || 'assistant';
    container.className = `message-bubble ${role === 'user' ? 'user' : 'assistant'}`;
    container.setAttribute('dir', 'auto');
    
    let bodyText = msg.content || "";
    
    // Parse QML custom role payloads from the content column
    let isCommand = (role === "system_command");
    let commandCode = "";
    let commandOutput = "";
    let commandStatus = "";
    let displayPattern = "";
    
    if (isCommand) {
        try {
            let parsed = JSON.parse(bodyText);
            commandCode = parsed.command || "";
            commandOutput = parsed.output || "";
            commandStatus = parsed.status || "";
            displayPattern = parsed.displayPattern || "";
            bodyText = displayPattern 
                ? `🔍 Searched local files for \`${displayPattern}\``
                : `⚙ Ran command: \`${commandCode}\``;
        } catch (e) {
            commandCode = bodyText;
            commandStatus = "error";
        }
    }
    
    let isMemory = (role === "memory");
    let memoryContent = "";
    let memoryId = "";
    if (isMemory) {
        try {
            let parsed = JSON.parse(bodyText);
            memoryId = parsed.id || "";
            memoryContent = parsed.content || "";
            bodyText = "";
        } catch (e) {
            memoryContent = bodyText;
            bodyText = "";
        }
    }
    
    let isTask = (role === "task");
    let taskTitle = "";
    let taskId = "";
    if (isTask) {
        try {
            let parsed = JSON.parse(bodyText);
            taskId = parsed.id || "";
            taskTitle = parsed.title || "";
            bodyText = "";
        } catch (e) {
            taskTitle = bodyText;
            bodyText = "";
        }
    }

    let isSetting = (role === "setting_approval");
    let settingCmd = "";
    let settingDesc = "";
    if (isSetting) {
        let parts = bodyText.split("\n\n");
        settingCmd = parts[0] || "";
        settingDesc = parts.slice(1).join("\n\n") || "";
        bodyText = "";
    }
    
    let isOpenCode = (role === "opencode_approval");
    let opencodeInstruction = "";
    let opencodeFiles = "";
    let opencodeModel = "";
    let opencodeStatus = "pending";
    let opencodeOutput = "";
    if (isOpenCode) {
        try {
            let parsed = JSON.parse(bodyText);
            opencodeInstruction = parsed.instruction || "";
            opencodeFiles = parsed.files || "";
            opencodeModel = parsed.model || "";
            opencodeStatus = parsed.status || "pending";
            opencodeOutput = parsed.output || "";
        } catch (e) {
            opencodeInstruction = bodyText;
        }
        bodyText = "";
    }
    
    // 1. Thinking/Reasoning block extraction & collapsible rendering
    let thinkingText = '';
    const startTag = "<thinking>";
    const endTag = "</thinking>";
    const startIdx = bodyText.indexOf(startTag);
    if (startIdx !== -1) {
        const endIdx = bodyText.indexOf(endTag, startIdx + startTag.length);
        if (endIdx !== -1) {
            thinkingText = bodyText.substring(startIdx + startTag.length, endIdx).trim();
            bodyText = (bodyText.substring(0, startIdx) + bodyText.substring(endIdx + endTag.length)).trim();
        } else {
            thinkingText = bodyText.substring(startIdx + startTag.length).trim();
            bodyText = bodyText.substring(0, startIdx).trim();
        }
    }
    
    if (thinkingText) {
        const details = document.createElement('details');
        details.className = 'thinking-details';
        details.innerHTML = `
            <summary class="thinking-summary">Reasoning Details</summary>
            <div class="thinking-content" dir="auto">${escapeHtml(thinkingText)}</div>
        `;
        container.appendChild(details);
    }
    
    // 2. Body Text Markdown Render
    if (bodyText) {
        const textSpan = document.createElement('span');
        textSpan.setAttribute('dir', 'auto');
        textSpan.innerHTML = parseMarkdown(bodyText);
        container.appendChild(textSpan);
    }
    
    // 3. Command Result/Remote execution approval card (Path C)
    if (isCommand) {
        const commandCard = document.createElement('div');
        commandCard.className = 'card-wrapper command';
        
        const status = commandStatus || 'pending';
        const badgeClass = `status-${status}`;
        const badgeLabel = status === 'completed' || status === 'success' ? 'Success' : status === 'pending' ? 'Pending Approval' : status.toUpperCase();
        
        let cardHtml = `
            <div class="card-header-row">
                <span>💻 Shell Command</span>
                <span class="card-badge ${badgeClass}">${badgeLabel}</span>
            </div>
            <div class="command-code-display">${escapeHtml(commandCode)}</div>
        `;
        
        // Show approval/decline buttons for pending remote actions
        if (status === 'pending') {
            cardHtml += `
                <div class="mobile-tool-prompt">
                    <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="flex-shrink:0"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>
                    <span>This command requires local verification before executing.</span>
                </div>
                <div class="card-actions-row">
                    <button class="card-btn approve" onclick="handleCommandAction('${msg.id}', 'approve', this)">Approve and Execute</button>
                    <button class="card-btn decline" onclick="handleCommandAction('${msg.id}', 'decline', this)">Decline</button>
                </div>
            `;
        } else if (status === 'running') {
            cardHtml += `
                <div style="font-size:0.75rem; color:var(--muted-foreground); text-align:center; padding: 4px;">
                    Executing command on host...
                </div>
            `;
        }
        
        // Display terminal output if execution completed
        if (commandOutput) {
            cardHtml += `
                <div class="command-terminal-output">${escapeHtml(commandOutput)}</div>
            `;
        }
        
        commandCard.innerHTML = cardHtml;
        container.appendChild(commandCard);
    }
    
    // Setting approval card
    if (isSetting) {
        const settingCard = document.createElement('div');
        settingCard.className = 'card-wrapper command';
        settingCard.innerHTML = `
            <div class="card-header-row">
                <span>⚙ Setting Approval</span>
                <span class="card-badge status-pending">Pending Approval</span>
            </div>
            <div class="command-code-display">${escapeHtml(settingCmd)}</div>
            <div style="font-size: 0.85rem; color: var(--muted-foreground); margin: 4px 0;">${escapeHtml(settingDesc)}</div>
            <div class="card-actions-row">
                <button class="card-btn approve" onclick="handleCommandAction('${msg.id}', 'approve', this)">Approve Change</button>
                <button class="card-btn decline" onclick="handleCommandAction('${msg.id}', 'decline', this)">Decline</button>
            </div>
        `;
        container.appendChild(settingCard);
    }
    
    // OpenCode approval card
    if (isOpenCode) {
        const opencodeCard = document.createElement('div');
        opencodeCard.className = 'card-wrapper command';
        
        const badgeClass = `status-${opencodeStatus}`;
        const badgeLabel = opencodeStatus === 'completed' || opencodeStatus === 'success' ? 'Success' : opencodeStatus === 'pending' ? 'Pending Approval' : opencodeStatus.toUpperCase();
        
        let initialModel = opencodeModel || 'opencode/mimo-v2.5-free';
        let cardHtml = `
            <div class="card-header-row">
                <span>💻 OpenCode Approval</span>
                <span class="card-badge ${badgeClass}">${badgeLabel}</span>
            </div>
        `;

        if (opencodeStatus === 'pending') {
            cardHtml += `
                <div class="opencode-model-select-row" style="margin: 8px 0; display: flex; align-items: center; gap: 8px;">
                    <span style="font-size: 0.8rem; font-weight: bold; min-width: 60px;">Model:</span>
                    <select class="opencode-model-select" style="flex: 1; padding: 4px; border-radius: 4px; background: var(--input); color: var(--foreground); border: 1px solid var(--border); font-size: 0.8rem;" onchange="window.updateOpenCodeCommandPreview(this, '${escapeHtml(opencodeInstruction).replace(/'/g, "\\'")}', '${escapeHtml(opencodeFiles).replace(/'/g, "\\'")}')">
                        <option value="opencode/mimo-v2.5-free" ${initialModel === 'opencode/mimo-v2.5-free' ? 'selected' : ''}>opencode/mimo-v2.5-free (Remote Free)</option>
                        <option value="opencode/deepseek-v4-flash-free" ${initialModel === 'opencode/deepseek-v4-flash-free' ? 'selected' : ''}>opencode/deepseek-v4-flash-free (Remote Free)</option>
                        <option value="opencode/claude-sonnet-4-6" ${initialModel === 'opencode/claude-sonnet-4-6' ? 'selected' : ''}>opencode/claude-sonnet-4-6</option>
                        <option value="opencode/gpt-5.4-mini" ${initialModel === 'opencode/gpt-5.4-mini' ? 'selected' : ''}>opencode/gpt-5.4-mini</option>
                        <option value="ollama/gemma4" ${initialModel === 'ollama/gemma4' ? 'selected' : ''}>ollama/gemma4 (Local)</option>
                        <option value="" ${initialModel === '' ? 'selected' : ''}>Default (from config)</option>
                    </select>
                </div>
            `;
        } else if (opencodeModel) {
            cardHtml += `<div style="font-size: 0.8rem; color: var(--muted-foreground); margin: 2px 0;"><strong>Model:</strong> ${escapeHtml(opencodeModel)}</div>`;
        }

        // Build command display string
        let displayCmd = `opencode run "${escapeHtml(opencodeInstruction)}"`;
        if (opencodeFiles) {
            opencodeFiles.split(',').forEach(f => {
                f = f.trim();
                if (f) displayCmd += ` -f "${escapeHtml(f)}"`;
            });
        }
        if (opencodeStatus === 'pending') {
            if (initialModel) displayCmd += ` --model "${escapeHtml(initialModel)}"`;
        } else if (opencodeModel) {
            displayCmd += ` --model "${escapeHtml(opencodeModel)}"`;
        }

        cardHtml += `
            <div class="command-code-display" style="white-space: pre-wrap; font-family: monospace; font-size: 0.8rem; background: var(--secondary); padding: 8px; border-radius: 4px; border: 1px solid var(--border); margin: 6px 0;">${displayCmd}</div>
            <div style="font-size: 0.85rem; color: var(--muted-foreground); margin: 4px 0;">${escapeHtml(opencodeInstruction)}</div>
        `;
        if (opencodeFiles) {
            cardHtml += `<div style="font-size: 0.8rem; color: var(--muted-foreground); margin: 2px 0;"><strong>Files:</strong> ${escapeHtml(opencodeFiles)}</div>`;
        }
        
        if (opencodeStatus === 'pending') {
            cardHtml += `
                <div class="card-actions-row">
                    <button class="card-btn approve" onclick="handleCommandAction('${msg.id}', 'approve', this)">Approve and Run</button>
                    <button class="card-btn decline" onclick="handleCommandAction('${msg.id}', 'decline', this)">Decline</button>
                </div>
            `;
        } else if (opencodeStatus === 'running') {
            cardHtml += `
                <div style="font-size:0.75rem; color:var(--muted-foreground); text-align:center; padding: 4px;">
                    Executing OpenCode run on host...
                </div>
            `;
        }
        
        if (opencodeOutput) {
            cardHtml += `
                <div class="command-terminal-output" style="white-space: pre-wrap; font-family: monospace; font-size: 0.8rem; background: #000; color: #0f0; padding: 8px; border-radius: 4px; margin-top: 6px; max-height: 300px; overflow-y: auto;">${escapeHtml(opencodeOutput)}</div>
            `;
        }
        
        opencodeCard.innerHTML = cardHtml;
        container.appendChild(opencodeCard);
    }
    
    // 4. Task Saved Indicator Card (Path C)
    if (isTask) {
        const taskCard = document.createElement('div');
        taskCard.className = 'card-wrapper task';
        taskCard.innerHTML = `
            <div class="card-header-row">
                <span>✅ Task Registered</span>
            </div>
            <div class="card-body-content">${escapeHtml(taskTitle)}</div>
        `;
        container.appendChild(taskCard);
    }
    
    // 5. Memory Saved Indicator Card (Path C)
    if (isMemory) {
        const memoryCard = document.createElement('div');
        memoryCard.className = 'card-wrapper memory';
        memoryCard.innerHTML = `
            <div class="card-header-row">
                <span>🧠 Memory Registered</span>
            </div>
            <div class="card-body-content"><em>"${escapeHtml(memoryContent)}"</em></div>
        `;
        container.appendChild(memoryCard);
    }
    
    chatFlow.appendChild(container);
    return container;
}

// Helper to dynamically update the command line preview when model selector changes
window.updateOpenCodeCommandPreview = function(selectEl, instruction, files) {
    const card = selectEl.closest('.card-wrapper');
    const display = card.querySelector('.command-code-display');
    const model = selectEl.value;
    let cmd = `opencode run "${instruction}"`;
    if (files) {
        files.split(',').forEach(f => {
            f = f.trim();
            if (f) cmd += ` -f "${f}"`;
        });
    }
    if (model) {
        cmd += ` --model "${model}"`;
    }
    display.textContent = cmd;
};

// Global action handler for interactive remote command triggers
window.handleCommandAction = async function(messageId, action, btnElement) {
    const card = btnElement.closest('.card-wrapper');
    const selectEl = card.querySelector('.opencode-model-select');
    const selectedModel = selectEl ? selectEl.value : null;

    const actionsRow = card.querySelector('.card-actions-row');
    const promptRow = card.querySelector('.mobile-tool-prompt');
    const badge = card.querySelector('.card-badge');
    const modelRow = card.querySelector('.opencode-model-select-row');
    
    if (actionsRow) actionsRow.remove();
    if (promptRow) promptRow.remove();
    if (modelRow) {
        // Replace model select dropdown row with a static text label if approved
        if (action === 'approve' && selectedModel) {
            const staticModel = document.createElement('div');
            staticModel.style.fontSize = '0.8rem';
            staticModel.style.color = 'var(--muted-foreground)';
            staticModel.style.margin = '2px 0';
            staticModel.innerHTML = `<strong>Model:</strong> ${escapeHtml(selectedModel)}`;
            modelRow.replaceWith(staticModel);
        } else {
            modelRow.remove();
        }
    }
    
    // Update badge status UI locally
    badge.className = `card-badge status-${action === 'approve' ? 'running' : 'declined'}`;
    badge.textContent = action === 'approve' ? 'Running...' : 'Declined';
    
    try {
        const reqBody = { message_id: messageId, action: action };
        if (action === 'approve' && selectedModel !== null) {
            reqBody.model = selectedModel;
        }
        const response = await fetch(`/api/commands/action?token=${activeToken}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(reqBody)
        });
        
        if (response.ok) {
            const result = await response.json();
            // Update with completed status & terminal output
            badge.className = `card-badge status-${result.status}`;
            badge.textContent = result.status === 'completed' ? 'Success' : result.status.toUpperCase();
            
            if (result.output) {
                // If there's already a terminal display, remove it first
                const oldOutput = card.querySelector('.command-terminal-output');
                if (oldOutput) oldOutput.remove();
                
                const terminal = document.createElement('div');
                terminal.className = 'command-terminal-output';
                terminal.textContent = result.output;
                card.appendChild(terminal);
            }
            scrollToBottom();
            
            // Reload side tabs if any task/memory status changes
            if (currentTab === 'tasks') loadTasks();
            if (currentTab === 'memories') loadMemories();
        } else {
            badge.className = 'card-badge status-error';
            badge.textContent = 'Failed';
        }
    } catch (e) {
        badge.className = 'card-badge status-error';
        badge.textContent = 'Connection Error';
    }
};

// ── Submit Prompt & SSE Streaming ──────────────────────────
async function submitPrompt() {
    const text = promptInput.value.trim();
    if (!text) return;
    
    promptInput.value = '';
    promptInput.style.height = 'auto'; // Reset input size
    
    // Render user message bubble locally
    appendMessageBubble({ role: 'user', content: text });
    scrollToBottom();
    
    // Append loading assistant bubble container
    const assistantBubble = appendMessageBubble({ role: 'assistant', content: '' });
    const textSpan = document.createElement('span');
    textSpan.textContent = 'Generating response...';
    assistantBubble.appendChild(textSpan);
    
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
            textSpan.textContent = 'Error: Failed to connect to local LLM backend.';
            return;
        }
        
        textSpan.remove(); // Clear placeholder
        
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
                            
                            // Re-render elements dynamically inside the assistant bubble
                            assistantBubble.innerHTML = '';
                            
                            // Extract thinking block
                            let bodyText = fullContent;
                            let thinkingText = '';
                            const startTag = "<thinking>";
                            const endTag = "</thinking>";
                            const startIdx = fullContent.indexOf(startTag);
                            if (startIdx !== -1) {
                                const endIdx = fullContent.indexOf(endTag, startIdx + startTag.length);
                                if (endIdx !== -1) {
                                    thinkingText = fullContent.substring(startIdx + startTag.length, endIdx).trim();
                                    bodyText = (fullContent.substring(0, startIdx) + fullContent.substring(endIdx + endTag.length)).trim();
                                } else {
                                    thinkingText = fullContent.substring(startIdx + startTag.length).trim();
                                    bodyText = fullContent.substring(0, startIdx).trim();
                                }
                            }
                            
                            // Render reasoning details
                            if (thinkingText) {
                                const details = document.createElement('details');
                                details.className = 'thinking-details';
                                // Keep open during generation
                                details.setAttribute('open', '');
                                details.innerHTML = `
                                    <summary class="thinking-summary">Reasoning...</summary>
                                    <div class="thinking-content" dir="auto">${escapeHtml(thinkingText)}</div>
                                `;
                                assistantBubble.appendChild(details);
                            }
                            
                            // Render body text
                            if (bodyText) {
                                const span = document.createElement('span');
                                span.setAttribute('dir', 'auto');
                                span.innerHTML = parseMarkdown(bodyText);
                                assistantBubble.appendChild(span);
                            }
                            
                            scrollToBottom();
                        } else if (data.error) {
                            textSpan.textContent = data.error;
                            assistantBubble.appendChild(textSpan);
                        }
                    } catch (e) {
                        // Chunk parsing error
                    }
                }
            }
        }
        
        // After streaming is completed, reload all database messages to fetch full structured schema
        // (including parsed task/memory/command fields from DB)
        await reloadMessages();
        
        // Refresh sidebar lists
        loadSessions();
        if (currentTab === 'tasks') loadTasks();
        if (currentTab === 'memories') loadMemories();
        
    } catch (e) {
        textSpan.textContent = 'Network Error. Could not establish stream connection.';
        assistantBubble.appendChild(textSpan);
    }
}

// Helper utilities
function scrollToBottom() {
    chatFlow.scrollTop = chatFlow.scrollHeight;
}

function escapeHtml(text) {
    if (!text) return "";
    return text
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
}

// Start
init();
