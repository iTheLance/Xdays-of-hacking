# Day 3 - HTTP/HTTPS

## What this day is about

HTTP is the foundation of the web and therefore the foundation of web hacking. Every web vulnerability like XSS, CSRF, SQLi, and broken auth rides on top of HTTP. You cannot hack what you do not understand, so this day is about understanding the protocol at the wire level, not just the browser level.

## The Request/Response Model

Every interaction on the web is a request and a response. You ask, the server answers. The client sends a request containing a method, URL, headers, and an optional body. The server sends back a response containing a status code, headers, and a body.

HTTP is stateless which means the server remembers nothing between requests. Cookies exist to work around this limitation.

HTTPS is just HTTP with a TLS layer on top. The TLS handshake happens first, encrypts the channel, then HTTP runs inside it. The encryption protects the data in transit but the server and any proxy you go through can still see everything.

## HTTP Methods

GET is used to fetch a resource and carries no body. POST is used to submit data and carries a body. PUT replaces or updates a resource. DELETE removes one. OPTIONS asks the server what methods it supports. HEAD works like GET but the response has no body, just the headers.

From a hacking perspective, servers sometimes lock down GET but forget to lock down POST to the same endpoint, or allow PUT and DELETE on endpoints that should be read only. Always probe all methods when testing a target.

## Status Codes

200 means the request completed successfully. 201 means something was created and you should check what. 301 and 302 are redirects and can leak internal URLs in the Location header. 400 means the server rejected your input so you tweak it and try again. 401 means auth is required and you have not provided any. 403 means you are authenticated but not allowed. 404 means the resource does not exist. 405 means try a different method. 500 means the server broke and you should look for info leakage in the response body. 503 means the server is overloaded or down.

The 401 vs 403 distinction is important. 401 tells you that you are not logged in. 403 tells you that you are logged in but do not have enough permissions. Both are useful signals during recon.

## Headers

Headers are metadata attached to every request and response. They control caching, authentication, content type, security policies and more.

On the request side, the Host header tells the server which virtual host you want and is critical for vhost enumeration and Host header injection attacks. User-Agent identifies your client and is trivially spoofable so any server that trusts it for access control is broken. The Cookie header carries your session and stealing it means stealing the session. Authorization carries tokens like Basic or Bearer JWT. Content-Type tells the server how to parse your body and changing it can break parsers or enable injection. X-Forwarded-For carries the original client IP when going through a proxy and applications that trust this header for IP based controls are completely bypassable.

On the response side, Set-Cookie sets a cookie and you should always check it for the HttpOnly, Secure and SameSite flags. Content-Security-Policy controls what the browser can load and a weak CSP makes XSS easier. X-Frame-Options prevents clickjacking and if it is missing the page may be vulnerable. The Server header leaks what software is running which is information attackers should not get for free.

## What I Did

### DevTools on TryHackMe

Opened DevTools on tryhackme.com, went to the Network tab and clicked on the csrf request to inspect it.

**[SCREENSHOT: DevTools Network tab showing all requests on tryhackme.com]**

**[SCREENSHOT: Response headers for the csrf request]**

Looking at the response headers I could see that the Cf-Ray value ended in LOS which tells you TryHackMe sits behind Cloudflare and that the Lagos edge node served the request. The Cache-Control was set to public, max-age=0, must-revalidate which makes sense for a CSRF token since you never want a stale one. Content-Encoding was br meaning Brotli compression was used. Content-Type was application/json meaning this is an API endpoint.

**[SCREENSHOT: Request headers for the csrf request]**

The request headers had the colon prefixed pseudo-headers like :method, :path and :scheme which tells you HTTP/2 was being used. The Accept-Language header was set to en-GB and en-US which leaks your locale. The Cookie header was present since I was already logged in.

### curl GET Request

```bash
curl -v https://httpbin.org/get 2>&1 | head -60
```

Watching the verbose output I could see the full TLS handshake happen before any HTTP data was exchanged. DNS resolved to multiple IPs which means the service is load balanced. TLS 1.2 was negotiated with the cipher suite ECDHE-RSA-AES128-GCM-SHA256. The certificate was issued by Amazon and verified via OpenSSL. After ALPN negotiation, HTTP/2 was used for the actual request.

### curl POST with Spoofed User-Agent

```bash
curl -v -X POST https://httpbin.org/post \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=lance&password=supersecret"
```

The server received the fake User-Agent and believed it completely. There is no verification possible on the server side. The POST body was parsed as form data and echoed back as JSON. My real public IP still appeared in the origin field but has been redacted here. AWS also injected an X-Amzn-Trace-Id header automatically which I never sent.

curl also warned me that using -X POST was unnecessary since it already infers POST when you use -d to send data.

### curl Cookies

```bash
curl -v -c cookies.txt "https://httpbin.org/cookies/set?session=abc123&user=lance"
cat cookies.txt
```

The server responded with a 302 redirect and two Set-Cookie headers. The cookies were saved to cookies.txt in Netscape format. These cookies had no HttpOnly flag meaning JavaScript could read and steal them. No Secure flag meaning they would be sent over plain HTTP too. No SameSite flag meaning they could be sent on cross-site requests which opens up CSRF. The expiry was 0 meaning they were session cookies that die when the browser closes.

## Cookies Deep Dive

Cookies are the primary way web apps maintain state across stateless HTTP requests. The security flags on cookies matter a lot. HttpOnly stops JavaScript from reading the cookie so XSS cannot steal it. Secure ensures the cookie only travels over HTTPS. SameSite=Strict means the cookie will not be sent on cross-site requests which prevents CSRF. SameSite=Lax gives partial protection. A session cookie with none of these flags is basically unprotected and is a target the moment you find an XSS or a way to force a cross-site request.

## HTTP Versions

HTTP/1.0 introduced headers and made the protocol flexible. HTTP/1.1 added keep-alive connections so a new TCP handshake was not needed for every single request. HTTP/2 is binary, multiplexes multiple requests over one connection, and compresses headers. This is what you will see on modern targets. HTTP/3 runs over QUIC which uses UDP instead of TCP and reduces handshake overhead further.

The practical impact is that HTTP/2 is a binary protocol so you cannot just open a raw TCP connection and type HTTP requests by hand anymore. Use curl or Burp Suite.

## Key Takeaways

HTTP is stateless and cookies are the fix for that. Headers are fully controllable by the client so they should never be trusted server-side for security decisions. User-Agent, Referer and X-Forwarded-For are all trivially spoofable. Cookie flags are your first checkpoint when looking at web app authentication. The 401 vs 403 distinction tells you whether auth is missing or just insufficient. TLS certificate information leaks the org details, hosting provider and expiry dates which is useful during recon.

## Resources
- [httpbin.org](https://httpbin.org) for testing HTTP requests against a real server
- [MDN HTTP docs](https://developer.mozilla.org/en-US/docs/Web/HTTP) as a reference for everything HTTP
- [curl man page](https://curl.se/docs/manpage.html) because you will use curl constantly
