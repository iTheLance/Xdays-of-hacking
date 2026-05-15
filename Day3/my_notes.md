# Day 3 — HTTP/HTTPS

## What this day is about
HTTP is the foundation of the web and therefore the foundation of web hacking. Every web vulnerability — XSS, CSRF, SQLi, broken auth — rides on top of HTTP. You can't hack what you don't understand, so this day is about understanding the protocol at the wire level, not just the browser level.

---

## The Request/Response Model

Every interaction on the web is a request and a response. You ask, the server answers. That's it.

- **Client** sends a **request** — method, URL, headers, optional body
- **Server** sends a **response** — status code, headers, body

HTTP is **stateless** — the server remembers nothing between requests. Cookies exist to work around this.

HTTPS is just HTTP with a TLS layer on top. The TLS handshake happens first, encrypts the channel, then HTTP runs inside it.

---

## HTTP Methods

| Method | Purpose |
|--------|---------|
| GET | Fetch a resource — no body |
| POST | Submit data — has a body |
| PUT | Replace/update a resource |
| DELETE | Delete a resource |
| OPTIONS | Ask what methods are allowed |
| HEAD | Same as GET but response has no body — just headers |

From a hacking perspective: servers sometimes lock down GET but forget to lock down POST to the same endpoint, or allow PUT/DELETE on endpoints that should be read-only. Always probe all methods.

---

## Status Codes

| Code | Meaning | Hacker relevance |
|------|---------|-----------------|
| 200 | OK | Normal response |
| 201 | Created | Something was created — check what |
| 301/302 | Redirect | Can leak internal URLs in `Location` header |
| 400 | Bad Request | Server rejected your input — tweak it |
| 401 | Unauthorized | Auth required — no token/session sent |
| 403 | Forbidden | Auth present but not enough permissions |
| 404 | Not Found | Resource doesn't exist |
| 405 | Method Not Allowed | Try a different method |
| 500 | Internal Server Error | You broke something — look for info leakage in the body |
| 503 | Service Unavailable | Server overloaded or down |

**401 vs 403** is a key distinction — 401 means "you're not logged in", 403 means "you're logged in but not allowed". Both are useful signals during recon.

---

## Headers

Headers are metadata attached to every request and response. They control caching, auth, content type, security policies, and more.

### Request headers you'll manipulate constantly

- `Host` — which virtual host you want. Critical for vhost enumeration and Host header injection attacks
- `User-Agent` — identifies your client. Trivially spoofable — servers that trust this for access control are broken
- `Cookie` — your session. Steal this = steal the session
- `Authorization` — carries tokens (Basic, Bearer JWT, etc.)
- `Content-Type` — tells server how to parse your body. Changing this can break parsers or enable injection
- `Referer` — where you came from. Leaks browsing history, sometimes used for CSRF protection (badly)
- `X-Forwarded-For` — original client IP when going through a proxy. Apps that trust this for IP-based controls are bypassable

### Response headers that matter for security

- `Set-Cookie` — sets a cookie. Check for `HttpOnly`, `Secure`, `SameSite` flags
- `Content-Security-Policy` — controls what the browser can load. Weak CSP = XSS easier
- `X-Frame-Options` — prevents clickjacking. Missing = potential clickjacking
- `Server` — leaks what software is running. Info you shouldn't give attackers
- `Cache-Control` — controls caching. Sensitive pages with bad cache headers = data leakage

---

## What I Did

### DevTools on TryHackMe — inspecting a real request

Opened DevTools on tryhackme.com, Network tab, clicked the `csrf` request.

**[SCREENSHOT — DevTools Network tab showing all requests on tryhackme.com]**

**[SCREENSHOT — Response headers for the csrf request]**

Key observations:
- `Cf-Ray: 9fc38456a838b14b-LOS` — TryHackMe sits behind Cloudflare. `LOS` = Lagos edge node served me
- `Cache-Control: public, max-age=0, must-revalidate` — CSRF tokens must never be cached, this is correct
- `Content-Encoding: br` — Brotli compression
- `Content-Type: application/json` — this is an API endpoint, returns JSON

**[SCREENSHOT — Request headers for the csrf request]**

Key observations:
- `:method`, `:path`, `:scheme` pseudo-headers = HTTP/2
- `Accept-Language: en-GB,en-US;q=0.9` — leaks locale
- Cookie header was present (session already active) — redacted

### curl — raw GET request

```bash
curl -v https://httpbin.org/get 2>&1 | head -60
```

Watched the full TLS handshake in the terminal:
- DNS resolved to multiple IPs (load balanced)
- TLS 1.2 negotiated, cipher suite: `ECDHE-RSA-AES128-GCM-SHA256`
- Certificate issued by Amazon, verified via OpenSSL
- HTTP/2 used after ALPN negotiation
- Request sent, `200 OK` received

**[SCREENSHOT — curl -v output showing TLS handshake and HTTP/2 request]**

### curl — POST with spoofed User-Agent

```bash
curl -v -X POST https://httpbin.org/post \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=lance&password=supersecret"
```

What the server got back in the response body:
```json
"form": {
    "password": "supersecret",
    "username": "lance"
},
"origin": "xxx.xx.xx.xx"
```

Key points:
- Server received the fake User-Agent and believed it — no verification possible
- POST body was parsed as form data and echoed back
- Real public IP appeared in `origin` — headers can be spoofed, network layer cannot
- `X-Amzn-Trace-Id` was injected by AWS infrastructure automatically

### curl — cookies

```bash
curl -v -c cookies.txt "https://httpbin.org/cookies/set?session=abc123&user=lance"
cat cookies.txt
```

Server responded with `302` redirect and two `Set-Cookie` headers:
```
set-cookie: session=abc123; Path=/
set-cookie: user=lance; Path=/
```

cookies.txt saved them in Netscape format. These cookies had:
- No `HttpOnly` flag — accessible via JavaScript, vulnerable to XSS theft
- No `Secure` flag — would be sent over plain HTTP too
- No `SameSite` flag — can be sent cross-site, CSRF risk
- `expire 0` — session cookie, dies on browser close

---

## Cookies Deep Dive

Cookies are the primary way web apps maintain state across requests. The security flags matter enormously:

| Flag | What it does | Missing = |
|------|-------------|-----------|
| `HttpOnly` | JS can't read the cookie | XSS can steal session |
| `Secure` | Only sent over HTTPS | Cookie sent in plaintext over HTTP |
| `SameSite=Strict` | Not sent on cross-site requests | CSRF possible |
| `SameSite=Lax` | Sent on top-level navigations | Partial CSRF protection |

A session cookie with none of these flags set is basically unprotected.

---

## HTTP Versions — Why it matters

| Version | Key feature | Notes |
|---------|------------|-------|
| HTTP/1.0 | Headers introduced | New TCP connection per request |
| HTTP/1.1 | Keep-alive, pipelining | Most common for years |
| HTTP/2 | Binary, multiplexed, header compression | What you saw in curl and DevTools |
| HTTP/3 | Runs over QUIC (UDP) instead of TCP | Faster, less handshake overhead |

HTTP/2 is what you'll deal with on modern targets. Binary protocol means you can't just netcat into port 80 and type requests anymore — use curl or Burp.

---

## Key Takeaways

- HTTP is stateless — cookies are the patch for that
- Headers are fully controllable by the client — never trust them server-side for security decisions
- User-Agent, Referer, X-Forwarded-For are all trivially spoofable
- HTTPS encrypts the body and headers in transit — but the server and any proxy you go through can still see everything
- Cookie flags (`HttpOnly`, `Secure`, `SameSite`) are your first check when looking at web app auth
- `401 vs 403` tells you whether auth is missing or just insufficient
- TLS certificate info leaks org details, hosting provider, and expiry dates — useful for recon

---

## Resources
- [httpbin.org](https://httpbin.org) — test HTTP requests against a real server
- [MDN HTTP docs](https://developer.mozilla.org/en-US/docs/Web/HTTP) — reference for everything HTTP
- [curl man page](https://curl.se/docs/manpage.html) — you'll use curl constantly
