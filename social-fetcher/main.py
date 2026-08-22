from urllib.parse import quote_plus

from flask import jsonify, request
from playwright.sync_api import sync_playwright

from app import (
    BROWSER_TIMEOUT_MS,
    THREADS_BASE_URL,
    THREADS_SCROLLS,
    _BROWSER_GATE,
    _browser_context,
    _clean_text,
    _iso,
    _limit,
    _threads_dom_items,
    app,
)


def _threads_query(value):
    query = _clean_text(value)
    if len(query) < 2 or len(query) > 160:
        raise ValueError("Threads search query must be 2-160 characters")
    return query


def fetch_threads_search(payload):
    query = _threads_query(payload.get("query") or payload.get("target"))
    limit = _limit(payload.get("limit"), 50)
    # Threads' logged-out Recent search is public. The explicit filter keeps
    # candidate discovery fresh; /hiring applies its own three-month retention
    # after parsing the returned post timestamps.
    url = (
        f"{THREADS_BASE_URL}/search?q={quote_plus(query)}"
        "&serp_type=default&filter=recent"
    )

    with _BROWSER_GATE:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True)
            context = _browser_context(browser)
            page = context.new_page()
            page.set_default_timeout(BROWSER_TIMEOUT_MS)
            page.goto(url, wait_until="domcontentloaded", timeout=BROWSER_TIMEOUT_MS)

            collected = {}
            for _ in range(THREADS_SCROLLS):
                for item in _threads_dom_items(page):
                    collected[item["id"]] = item
                    if len(collected) >= limit:
                        break
                if len(collected) >= limit:
                    break
                page.mouse.wheel(0, 1800)
                page.wait_for_timeout(650)

            browser.close()

    items = []
    for item in list(collected.values())[:limit]:
        items.append(
            {
                "id": item["id"],
                "source": "threads",
                "target": query,
                "author": item.get("username") or "",
                "text": _clean_text(item.get("text")),
                "url": item.get("url") or "",
                "createdAt": _iso(item.get("createdAt")),
                "images": item.get("images") or [],
            }
        )

    return {
        "ok": True,
        "source": "threads",
        "mode": "search",
        "target": query,
        "query": query,
        "count": len(items),
        "items": items,
    }


@app.post("/threads/search")
def threads_search_route():
    payload = request.get_json(silent=True) or {}
    try:
        return jsonify(fetch_threads_search(payload))
    except ValueError as exc:
        return jsonify(ok=False, error=str(exc)), 400
    except Exception as exc:
        return jsonify(ok=False, error=f"{type(exc).__name__}: {exc}"), 502
