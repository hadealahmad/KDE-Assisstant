/*
 * KDE Assistant — AttachmentHelpers.js
 * File attachment utilities for multimodal messages
 */

.pragma library

var MAX_FILE_SIZE = 5 * 1024 * 1024; // 5 MB

var TEXT_EXTENSIONS = [
    "txt", "md", "markdown", "json", "jsonl", "js", "ts", "jsx", "tsx",
    "py", "rb", "go", "rs", "c", "cpp", "h", "hpp", "java", "kt",
    "sh", "bash", "zsh", "fish", "yaml", "yml", "toml", "ini", "cfg",
    "conf", "xml", "html", "css", "scss", "sql", "csv", "log", "env",
    "gitignore", "dockerfile", "makefile", "cmake", "gradle",
    "vue", "svelte", "lua", "r", "swift", "dart", "zig", "nim",
    "ex", "exs", "erl", "hs", "ml", "clj", "lisp", "el", "vim",
    "qmake", "pro", "pri", "qml", "qbs"
];

var IMAGE_EXTENSIONS = ["png", "jpg", "jpeg", "gif", "webp", "bmp"];
var PDF_EXTENSIONS = ["pdf"];

var MIME_TYPES = {
    "png": "image/png",
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "gif": "image/gif",
    "webp": "image/webp",
    "bmp": "image/bmp",
    "pdf": "application/pdf",
    "txt": "text/plain",
    "md": "text/markdown",
    "json": "application/json",
    "js": "text/javascript",
    "ts": "text/typescript",
    "py": "text/x-python",
    "html": "text/html",
    "css": "text/css",
    "xml": "application/xml",
    "yaml": "text/yaml",
    "yml": "text/yaml",
    "sh": "text/x-shellscript",
    "sql": "text/x-sql",
    "csv": "text/csv"
};

function getFileExtension(fileName) {
    if (!fileName) return "";
    var parts = fileName.toLowerCase().split(".");
    return parts.length > 1 ? parts[parts.length - 1] : "";
}

function isTextFile(fileName) {
    var ext = getFileExtension(fileName);
    if (ext === "" && fileName) {
        var lower = fileName.toLowerCase();
        return (lower === "makefile" || lower === "dockerfile" || lower === "gemfile"
             || lower === "rakefile" || lower === "procfile" || lower === "vagrantfile");
    }
    return TEXT_EXTENSIONS.indexOf(ext) !== -1;
}

function isImageFile(fileName) {
    return IMAGE_EXTENSIONS.indexOf(getFileExtension(fileName)) !== -1;
}

function isPdfFile(fileName) {
    return PDF_EXTENSIONS.indexOf(getFileExtension(fileName)) !== -1;
}

function isSupportedFile(fileName) {
    return isTextFile(fileName) || isImageFile(fileName) || isPdfFile(fileName);
}

function getMimeType(fileName) {
    var ext = getFileExtension(fileName);
    if (MIME_TYPES[ext]) return MIME_TYPES[ext];
    if (isTextFile(fileName)) return "text/plain";
    if (isImageFile(fileName)) return "image/" + ext;
    if (isPdfFile(fileName)) return "application/pdf";
    return "application/octet-stream";
}

function formatFileSize(bytes) {
    if (bytes < 1024) return bytes + " B";
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
    return (bytes / (1024 * 1024)).toFixed(1) + " MB";
}

function validateAttachment(fileSize, fileName) {
    if (!fileName || fileName.trim() === "") {
        return { valid: false, error: "No file selected" };
    }
    if (!isSupportedFile(fileName)) {
        var ext = getFileExtension(fileName);
        return { valid: false, error: "Unsupported file type: ." + (ext || "(no extension)") };
    }
    if (typeof fileSize === "number" && fileSize > MAX_FILE_SIZE) {
        return { valid: false, error: fileName + " exceeds 5 MB limit (" + formatFileSize(fileSize) + ")" };
    }
    return { valid: true, error: "" };
}

function createAttachmentObject(type, mimeType, fileName, filePath, data) {
    return {
        type: type,           // "text", "image", or "pdf"
        mimeType: mimeType,
        fileName: fileName,
        filePath: filePath,
        data: data            // text content or base64 string
    };
}

function parseAttachmentsJson(jsonStr) {
    if (!jsonStr || jsonStr === "") return [];
    try {
        var parsed = JSON.parse(jsonStr);
        return Array.isArray(parsed) ? parsed : [];
    } catch (e) {
        return [];
    }
}

function serializeAttachments(arr) {
    if (!arr || arr.length === 0) return "";
    return JSON.stringify(arr);
}
