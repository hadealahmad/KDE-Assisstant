/*
 * KDE Assistant — Search.js
 * Web search integration APIs (DuckDuckGo, Tavily, SearXNG, Google)
 */

.pragma library

function unescapeHtml(text) {
    if (!text) return "";
    return text
        .replace(/&amp;/g, "&")
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">")
        .replace(/&quot;/g, '"')
        .replace(/&#x27;/g, "'")
        .replace(/&#x2F;/g, "/")
        .replace(/&#39;/g, "'")
        .replace(/&nbsp;/g, " ");
}

function performDdgSearch(query, onSuccess, onError) {
    var url = "https://html.duckduckgo.com/html/?q=" + encodeURIComponent(query);
    var xhr = new XMLHttpRequest();
    xhr.open("GET", url, true);
    xhr.setRequestHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");

    xhr.onreadystatechange = function () {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                try {
                    var html = xhr.responseText;

                    if (html.indexOf("challenge-form") !== -1) {
                        onError("Search blocked by DuckDuckGo bot protection (challenge page).");
                        return;
                    }

                    var results = [];
                    var parts = html.split("class=\"result ");
                    if (parts.length <= 1) {
                        parts = html.split("class=\"web-result");
                    }

                    for (var i = 1; i < parts.length; i++) {
                        var part = parts[i];

                        var titleMatch = part.match(/class="result__a"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/);
                        if (!titleMatch) continue;

                        var href = titleMatch[1];
                        var title = titleMatch[2].replace(/<[^>]*>/g, "").trim();

                        var url = href;
                        var uddgMatch = href.match(/uddg=([^&]+)/);
                        if (uddgMatch) {
                            url = decodeURIComponent(uddgMatch[1]);
                        } else if (href.indexOf("//") === 0) {
                            url = "https:" + href;
                        }

                        var snippetMatch = part.match(/class="result__snippet"[^>]*>([\s\S]*?)<\/a>/);
                        var snippet = snippetMatch ? snippetMatch[1].replace(/<[^>]*>/g, "").trim() : "";

                        results.push({
                            title: unescapeHtml(title),
                            url: url,
                            snippet: unescapeHtml(snippet)
                        });
                        if (results.length >= 5) break;
                    }

                    if (results.length === 0) {
                        onSuccess("No search results found on DuckDuckGo.");
                        return;
                    }

                    var text = "Web Search Results:\n";
                    for (var k = 0; k < results.length; k++) {
                        text += (k + 1) + ". " + results[k].title + "\n   URL: " + results[k].url + "\n   Snippet: " + results[k].snippet + "\n\n";
                    }
                    onSuccess(text);
                } catch (e) {
                    onError("Failed to parse DuckDuckGo response: " + e.message);
                }
            } else {
                onError("DuckDuckGo search failed with HTTP " + xhr.status);
            }
        }
    };
    xhr.send();
}

function performTavilySearch(query, apiKey, onSuccess, onError) {
    var url = "https://api.tavily.com/search";
    var xhr = new XMLHttpRequest();
    xhr.open("POST", url, true);
    xhr.setRequestHeader("Content-Type", "application/json");
    var body = JSON.stringify({
        api_key: apiKey,
        query: query,
        search_depth: "basic",
        max_results: 5
    });
    xhr.onreadystatechange = function () {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                try {
                    var parsed = JSON.parse(xhr.responseText);
                    var text = "";
                    if (parsed.results && parsed.results.length > 0) {
                        for (var i = 0; i < parsed.results.length; i++) {
                            var res = parsed.results[i];
                            text += "Title: " + res.title + "\nURL: " + res.url + "\nContent: " + res.content + "\n\n";
                        }
                    } else {
                        text = "No search results found on Tavily.";
                    }
                    onSuccess(text);
                } catch (e) {
                    onError("Failed to parse Tavily response: " + e.message);
                }
            } else {
                onError("Tavily search failed with HTTP " + xhr.status);
            }
        }
    };
    xhr.send(body);
}

function performSearxngSearch(query, instanceUrl, onSuccess, onError) {
    var baseUrl = instanceUrl.replace(/\/$/, "");
    var url = baseUrl + "/search?q=" + encodeURIComponent(query) + "&format=json";
    var xhr = new XMLHttpRequest();
    xhr.open("GET", url, true);
    xhr.onreadystatechange = function () {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                try {
                    var parsed = JSON.parse(xhr.responseText);
                    var text = "";
                    if (parsed.results && parsed.results.length > 0) {
                        var count = Math.min(parsed.results.length, 5);
                        for (var i = 0; i < count; i++) {
                            var res = parsed.results[i];
                            text += "Title: " + res.title + "\nURL: " + res.url + "\nSnippet: " + (res.content || res.title) + "\n\n";
                        }
                    } else {
                        text = "No search results found on SearXNG.";
                    }
                    onSuccess(text);
                } catch (e) {
                    onError("Failed to parse SearXNG response: " + e.message);
                }
            } else {
                onError("SearXNG search failed with HTTP " + xhr.status);
            }
        }
    };
    xhr.send();
}

function performGoogleSearch(query, apiKey, cx, onSuccess, onError) {
    var url = "https://www.googleapis.com/customsearch/v1?key=" + encodeURIComponent(apiKey) +
        "&cx=" + encodeURIComponent(cx) +
        "&q=" + encodeURIComponent(query);
    var xhr = new XMLHttpRequest();
    xhr.open("GET", url, true);
    xhr.onreadystatechange = function () {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                try {
                    var parsed = JSON.parse(xhr.responseText);
                    var text = "";
                    if (parsed.items && parsed.items.length > 0) {
                        for (var i = 0; i < parsed.items.length; i++) {
                            var item = parsed.items[i];
                            text += "Title: " + item.title + "\nURL: " + item.link + "\nSnippet: " + item.snippet + "\n\n";
                        }
                    } else {
                        text = "No search results found on Google.";
                    }
                    onSuccess(text);
                } catch (e) {
                    onError("Failed to parse Google search response: " + e.message);
                }
            } else {
                onError("Google search failed with HTTP " + xhr.status);
            }
        }
    };
    xhr.send();
}

function executeSearch(query, config, onSuccess, onError) {
    var provider = config.searchProvider || "ddg";
    var apiKey = config.searchApiKey || "";
    var extraUrl = config.searchExtraUrl || "";

    if (provider === "tavily") {
        if (!apiKey || apiKey.trim() === "") {
            onError("Tavily API key is missing. Set it in settings.");
            return;
        }
        performTavilySearch(query, apiKey.trim(), onSuccess, onError);
    } else if (provider === "searxng") {
        if (!extraUrl || extraUrl.trim() === "") {
            onError("SearXNG Instance URL is missing. Set it in settings.");
            return;
        }
        performSearxngSearch(query, extraUrl.trim(), onSuccess, onError);
    } else if (provider === "google") {
        if (!apiKey || apiKey.trim() === "") {
            onError("Google Custom Search API key is missing. Set it in settings.");
            return;
        }
        if (!extraUrl || extraUrl.trim() === "") {
            onError("Google Search CX (Engine ID) is missing. Set it in settings.");
            return;
        }
        performGoogleSearch(query, apiKey.trim(), extraUrl.trim(), onSuccess, onError);
    } else {
        performDdgSearch(query, onSuccess, onError);
    }
}

function fetchWebpage(url, onSuccess, onError) {
    var jinaUrl = "https://r.jina.ai/" + url;
    var xhr = new XMLHttpRequest();
    xhr.open("GET", jinaUrl, true);

    xhr.onreadystatechange = function () {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                onSuccess(xhr.responseText);
            } else {
                fetchWebpageDirectly(url, onSuccess, onError);
            }
        }
    };
    xhr.send();
}

function fetchWebpageDirectly(url, onSuccess, onError) {
    var xhr = new XMLHttpRequest();
    xhr.open("GET", url, true);
    xhr.onreadystatechange = function () {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                var cleanText = stripHtml(xhr.responseText);
                onSuccess(cleanText);
            } else {
                onError("Failed to fetch webpage: HTTP " + xhr.status);
            }
        }
    };
    xhr.send();
}

function stripHtml(html) {
    if (!html) return "";
    return html
        .replace(/<script[^>]*>([\s\S]*?)<\/script>/gi, "")
        .replace(/<style[^>]*>([\s\S]*?)<\/style>/gi, "")
        .replace(/<[^>]*>/g, " ")
        .replace(/\s+/g, " ")
        .trim();
}

function escapeShellArg(arg) {
    if (!arg) return "''";
    return "'" + arg.replace(/'/g, "'\\''") + "'";
}

function buildGrepCommand(pattern, path, limit) {
    var maxCount = typeof limit === "number" ? limit : 20;
    var escapedPattern = escapeShellArg(pattern);
    var escapedPath = escapeShellArg(path || ".");
    return "grep -rnIE --max-count=" + maxCount + " " + escapedPattern + " " + escapedPath + " 2>/dev/null";
}

function buildRipgrepCommand(pattern, path, limit) {
    var maxCount = typeof limit === "number" ? limit : 20;
    var escapedPattern = escapeShellArg(pattern);
    var escapedPath = escapeShellArg(path || ".");
    return "rg --vimgrep --max-count=" + maxCount + " " + escapedPattern + " " + escapedPath + " 2>/dev/null";
}

