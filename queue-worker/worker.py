import json
import os
import socket
import time
import urllib.error
import urllib.request

TASK_API_URL = os.environ.get(
    "QUEUE_TASK_API_URL",
    "http://flat-finder-queue-task-api:4010",
).rstrip("/")
QUEUE_INTERNAL_KEY = os.environ.get("QUEUE_INTERNAL_KEY", "")
WORKER_ROLE = os.environ.get("QUEUE_WORKER_ROLE", "olx").strip().lower()
if WORKER_ROLE not in {"olx", "telegram"}:
    raise RuntimeError("QUEUE_WORKER_ROLE must be 'olx' or 'telegram'")

QUEUE_PROTOCOL_VERSION = max(3, int(os.environ.get("QUEUE_PROTOCOL_VERSION", "3")))
QUEUE_SHARDS = max(1, int(os.environ.get("QUEUE_SHARDS", "2")))
QUEUE_SHARD = max(0, int(os.environ.get("QUEUE_SHARD", "0"))) % QUEUE_SHARDS
POLL_SECONDS = max(0.2, float(os.environ.get("QUEUE_POLL_SECONDS", "1")))
IDLE_ERROR_SECONDS = max(1.0, float(os.environ.get("QUEUE_ERROR_RETRY_SECONDS", "5")))
EXECUTE_TIMEOUT = max(60, int(os.environ.get("QUEUE_EXECUTE_TIMEOUT_SECONDS", "180")))
WORKER_ID = os.environ.get("QUEUE_WORKER_ID") or (
    f"{socket.gethostname()}:{WORKER_ROLE}:{QUEUE_SHARD if WORKER_ROLE == 'olx' else 'tg'}"
)


def api_request(path, payload=None, timeout=30):
    if len(QUEUE_INTERNAL_KEY) < 16:
        raise RuntimeError("QUEUE_INTERNAL_KEY must be at least 16 characters")

    data = None
    method = "GET"
    headers = {
        "X-Queue-Key": QUEUE_INTERNAL_KEY,
        "User-Agent": "flat-finder-postgres-worker/1.0",
    }

    if payload is not None:
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        method = "POST"
        headers["Content-Type"] = "application/json"

    request = urllib.request.Request(
        f"{TASK_API_URL}{path}",
        method=method,
        data=data,
        headers=headers,
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read().decode("utf-8")
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as exc:
        try:
            body = exc.read().decode("utf-8")
            detail = json.loads(body).get("error") if body else None
        except Exception:
            detail = None
        raise RuntimeError(f"HTTP {exc.code}: {detail or exc.reason}") from exc


def worker_label():
    return "telegram" if WORKER_ROLE == "telegram" else f"olx:{QUEUE_SHARD}"


def task_matches_worker(payload):
    task_type = payload.get("type")
    if WORKER_ROLE == "telegram":
        return task_type == "flat.telegram.channel"
    try:
        shard = int(payload.get("crawlerShard") or 0) % QUEUE_SHARDS
    except (TypeError, ValueError):
        shard = 0
    return task_type == "flat.olx.page" and shard == QUEUE_SHARD


def fail_claimed_task(task_id, lock_token, error):
    return api_request(
        "/internal/queue-fail",
        payload={
            "id": task_id,
            "lockToken": lock_token,
            "error": str(error),
        },
        timeout=30,
    )


def process_claim(task):
    task_id = str(task.get("id") or "")
    lock_token = str(task.get("lockToken") or "")
    payload = task.get("payload") or {}
    label = worker_label()

    if not task_id or not lock_token:
        raise RuntimeError("claimed queue row is missing id or lock token")

    protocol = int(payload.get("queueProtocol") or 0)
    if protocol != QUEUE_PROTOCOL_VERSION or not task_matches_worker(payload):
        outcome = fail_claimed_task(
            task_id,
            lock_token,
            f"mismatched task protocol={protocol} type={payload.get('type')} shard={payload.get('crawlerShard')}",
        )
        print(
            f"[queue:worker:{label}] rejected mismatched task id={task_id} "
            f"protocol={protocol} type={payload.get('type')} "
            f"dead={1 if outcome.get('dead') else 0}",
            flush=True,
        )
        return

    try:
        result = api_request(
            "/internal/queue-task",
            payload=payload,
            timeout=EXECUTE_TIMEOUT,
        )
        completion = api_request(
            "/internal/queue-complete",
            payload={
                "id": task_id,
                "lockToken": lock_token,
                "result": result,
            },
            timeout=30,
        )
        if not completion.get("completed"):
            raise RuntimeError(f"task completion lost lease: {completion}")

        print(
            f"[queue:worker:{label}] completed {payload.get('type')} "
            f"country={payload.get('country')} city={payload.get('citySlug') or 'all'} "
            f"segment={payload.get('segment') or payload.get('channel') or '-'} "
            f"page={payload.get('page', '-')} fetched={result.get('fetched', 0)} "
            f"dedup={1 if result.get('deduplicated') else 0} "
            f"next={completion.get('queuedNext', 0)}",
            flush=True,
        )
    except Exception as exc:
        try:
            outcome = fail_claimed_task(task_id, lock_token, exc)
            target = "dead" if outcome.get("dead") else "retry"
            retry_ms = outcome.get("retryMs")
            retry_text = f" retryMs={retry_ms}" if retry_ms is not None else ""
        except Exception as fail_exc:
            target = "lease-expiry"
            retry_text = f" failTransition={fail_exc}"

        print(
            f"[queue:worker:{label}] failed type={payload.get('type')} "
            f"country={payload.get('country')} city={payload.get('citySlug') or 'all'} "
            f"segment={payload.get('segment') or payload.get('channel') or '-'} "
            f"page={payload.get('page', '-')} attempt={task.get('attempts', '?')} "
            f"target={target}{retry_text}: {exc}",
            flush=True,
        )


def worker_forever():
    label = worker_label()
    print(
        f"[queue:worker:{label}] polling PostgreSQL queue via API "
        f"protocol={QUEUE_PROTOCOL_VERSION} worker={WORKER_ID}",
        flush=True,
    )

    while True:
        try:
            response = api_request(
                "/internal/queue-claim",
                payload={
                    "role": WORKER_ROLE,
                    "shard": QUEUE_SHARD,
                    "workerId": WORKER_ID,
                },
                timeout=30,
            )
            task = response.get("task")
            if not task:
                time.sleep(POLL_SECONDS)
                continue

            process_claim(task)
        except Exception as exc:
            print(f"[queue:worker:{label}] poll error: {exc}", flush=True)
            time.sleep(IDLE_ERROR_SECONDS)


if __name__ == "__main__":
    worker_forever()
