# OLX fetcher sidecar.
#
# OLX's WAF (AWS CloudFront) 403s plain HTTP clients from our server by TLS/JA3
# fingerprint, but lets a real Chrome fingerprint through even from the same
# datacenter IP. curl_cffi's `impersonate` replicates that fingerprint, so this
# tiny service can fetch the SEO-facing HTML listing pages (NOT the blocked
# /api/v1 endpoint) and hand the flat-finder Node backend the structured ad
# objects embedded in each page's `window.__PRERENDERED_STATE__`.
#
# The Node backend owns all normalization/filtering; this only does the fetch +
# extract. Callers are expected to rate-limit (the Node side throttles per host).

import os
import re
import json

from flask import Flask, request, jsonify
from curl_cffi import requests as cffi

app = Flask(__name__)

# OLX real-estate landing path + Accept-Language per portal. These HTML pages
# carry __PRERENDERED_STATE__; they are not the guarded JSON API.
PORTALS = {
    "RO": ("https://www.olx.ro", "imobiliare", "ro-RO,ro;q=0.9,en;q=0.7"),
    "UA": ("https://www.olx.ua", "nedvizhimost", "uk-UA,uk;q=0.9,ru;q=0.7,en;q=0.5"),
    "KZ": ("https://www.olx.kz", "nedvizhimost", "ru-RU,ru;q=0.9,kk;q=0.7,en;q=0.5"),
    "UZ": ("https://www.olx.uz", "nedvizhimost", "ru-RU,ru;q=0.9,uz;q=0.7,en;q=0.5"),
}

# curl_cffi TLS/JA3 impersonation target. Override if a curl_cffi version needs a
# different label (e.g. "chrome131") — no code change required.
IMPERSONATE = os.environ.get("OLX_IMPERSONATE", "chrome124")
TIMEOUT = int(os.environ.get("OLX_TIMEOUT", "25"))

# window.__PRERENDERED_STATE__ = "<json string, escaped again as a JS string>";
_STATE_RE = re.compile(
    r'window\.__PRERENDERED_STATE__\s*=\s*("(?:[^"\\]|\\.)*")\s*;',
    re.S,
)


def extract_ads(html):
    """Return the list of ad objects from the page state, or None if not present."""
    m = _STATE_RE.search(html)
    if not m:
        return None
    try:
        # The value is a JSON string literal whose contents are themselves JSON.
        state = json.loads(json.loads(m.group(1)))
    except (ValueError, TypeError):
        return None
    ads = (((state or {}).get("listing") or {}).get("listing") or {}).get("ads")
    return ads if isinstance(ads, list) else None


@app.get("/health")
def health():
    return jsonify(ok=True)


@app.get("/olx/listings")
def olx_listings():
    code = (request.args.get("country") or "").upper()
    if code not in PORTALS:
        return jsonify(error="unknown country %r" % request.args.get("country")), 400
    try:
        page = max(1, int(request.args.get("page", "1")))
    except (TypeError, ValueError):
        page = 1

    host, path, accept_lang = PORTALS[code]
    # Newest first so the 3-week freshness window keeps as many live rows as it can.
    url = "%s/%s/?page=%d&search%%5Border%%5D=created_at%%3Adesc" % (host, path, page)
    try:
        resp = cffi.get(
            url,
            impersonate=IMPERSONATE,
            timeout=TIMEOUT,
            headers={"Accept-Language": accept_lang},
        )
    except Exception as e:  # network / TLS error
        return jsonify(error="fetch error: %s" % e), 502

    if resp.status_code != 200:
        return jsonify(error="OLX %s HTTP %d" % (code, resp.status_code)), 502

    ads = extract_ads(resp.text)
    if ads is None:
        return jsonify(error="OLX %s: no __PRERENDERED_STATE__ (blocked or markup change)" % code), 502

    return jsonify(country=code, page=page, count=len(ads), ads=ads)


if __name__ == "__main__":
    # Dev only; production uses gunicorn (see Dockerfile).
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "4020")))
