---
name: markdown-new
description: "Clean Markdown extraction from any URL via markdown.new (-80% токенов vs raw HTML). Use when operator says or implies: \"прочитай статью\", \"что в этой ссылке\", \"скачай страницу\", \"summarize this URL\", \"что пишут на habr/dev.to/medium\", или когда нужно процитировать содержимое article/blog/docs из URL. Do NOT use for: cross-source ресерч (perplexity-research), YouTube-видео (youtube-transcript), login-protected или JS-heavy SPA, real-time данные (биржа, livefeed)."
user-invocable: false
---

# markdown.new -- Clean Web Content

Converts any webpage to clean Markdown. Reduces tokens by ~80% compared to raw HTML.

## How to Use

Prepend `https://markdown.new/` to any URL:

```bash
curl -sL "https://markdown.new/https://example.com/article"
```

## When to Use

- Reading web pages, articles, blog posts
- Extracting documentation content
- Processing PDFs (built-in OCR)
- Getting clean text from any URL

## When NOT to Use

- JavaScript-heavy SPAs (React/Vue apps)
- Login-protected content
- Real-time data (stock prices, live feeds)
- Pages that require interaction

## Features

| Feature | Supported |
|---------|-----------|
| Web pages | Yes |
| PDFs | Yes (OCR) |
| Images | Yes (description) |
| Audio | Yes (transcription) |

## Integration Pattern

Instead of:
```bash
# Raw HTML -- wastes tokens
curl -sL "https://example.com/docs/guide"
```

Use:
```bash
# Clean Markdown -- 80% fewer tokens
curl -sL "https://markdown.new/https://example.com/docs/guide"
```

## Setup

No signup required. Free service. No API key needed.

## Fallback

If markdown.new is down, alternatives:
- [Jina AI Reader](https://r.jina.ai/) -- prepend `https://r.jina.ai/`
- [Trafilatura](https://trafilatura.readthedocs.io/) -- self-hosted Python library
