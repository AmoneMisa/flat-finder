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
    "UZ": {
        "host": "https://www.olx.uz",
        "lang": "ru-RU,ru;q=0.9,uz;q=0.7,en;q=0.5",
        "paths": {
            "flat:longRent": "nedvizhimost/kvartiry/arenda-dolgosrochnaya",
            "flat:sale": "nedvizhimost/kvartiry/prodazha",
        },
    },

    "KZ": {
        "host": "https://www.olx.kz",
        "lang": "ru-RU,ru;q=0.9,kk;q=0.7,en;q=0.5",
        "paths": {
            "flat:longRent": "nedvizhimost/arenda-kvartiry",
            "flat:sale": "nedvizhimost/prodazha-kvartiry",
        },
    },

    "UA": {
        "host": "https://www.olx.ua",
        "lang": "uk-UA,uk;q=0.9,ru;q=0.7,en;q=0.5",
        "paths": {
            "flat:longRent": "nedvizhimost/kvartiry/dolgosrochnaya-arenda-kvartir",
            "flat:sale": "nedvizhimost/kvartiry/prodazha-kvartir",
        },
    },

    "RO": {
        "host": "https://www.olx.ro",
        "lang": "ro-RO,ro;q=0.9,en;q=0.7",
        "paths": {
            "flat:longRent": "imobiliare/apartamente-garsoniere-de-inchiriat",
            "flat:sale": "imobiliare/apartamente-garsoniere-de-vanzare",
        },
    },
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
    segment = request.args.get("segment") or "flat:longRent"

    portal = PORTALS.get(code)
    if not portal:
        return jsonify(error=f"unknown country {code!r}"), 400

    path = portal["paths"].get(segment)
    if not path:
        return jsonify(error=f"unsupported OLX segment {segment!r}"), 400

    try:
        page = max(1, int(request.args.get("page", "1")))
    except (TypeError, ValueError):
        page = 1

    url = (
        f'{portal["host"]}/{path}/'
        f'?page={page}&search%5Border%5D=created_at%3Adesc'
    )

    try:
        resp = cffi.get(
            url,
            impersonate=IMPERSONATE,
            timeout=TIMEOUT,
            headers={"Accept-Language": portal["lang"]},
        )
    except Exception as e:
        return jsonify(error=f"fetch error: {e}"), 502

    if resp.status_code != 200:
        return jsonify(
            error=f"OLX {code} {segment} HTTP {resp.status_code}"
        ), 502

    ads = extract_ads(resp.text)

    if ads is None:
        return jsonify(
            error=f"OLX {code}: no __PRERENDERED_STATE__"
        ), 502

    return jsonify(
        country=code,
        segment=segment,
        page=page,
        count=len(ads),
        ads=ads,
    )


if __name__ == "__main__":
    # Dev only; production uses gunicorn (see Dockerfile).
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "4020")))
