import json
import os
import time
import urllib.request

import pika

RABBITMQ_URL = os.environ.get("RABBITMQ_URL", "amqp://crawler:crawler@flat-finder-rabbitmq:5672/%2F")
TASK_API_URL = os.environ.get("QUEUE_TASK_API_URL", "http://flat-finder-queue-task-api:4010").rstrip("/")
QUEUE_INTERNAL_KEY = os.environ.get("QUEUE_INTERNAL_KEY", "")
MODE = os.environ.get("QUEUE_MODE", "worker").strip().lower()
REFRESH_SECONDS = max(60, int(os.environ.get("QUEUE_REFRESH_SECONDS", "1800")))
PREFETCH = max(1, int(os.environ.get("QUEUE_PREFETCH", "1")))
MAX_ATTEMPTS = max(1, int(os.environ.get("QUEUE_MAX_ATTEMPTS", "5")))
# A queue task may legitimately wait on the HTTP task API for up to 180 seconds.
# pika.BlockingConnection cannot service heartbeat frames while the callback is
# blocked in urllib, so the previous 30s heartbeat guaranteed disconnects for
# slow OLX pages. Keep the heartbeat safely above the task timeout.
HEARTBEAT = max(240, int(os.environ.get("RABBITMQ_HEARTBEAT", "300")))
BLOCKED_CONNECTION_TIMEOUT = max(
    HEARTBEAT,
    int(os.environ.get("RABBITMQ_BLOCKED_CONNECTION_TIMEOUT", "360")),
)

MAIN_QUEUE = "crawl.flats.tasks"
RETRY_QUEUE = "crawl.flats.tasks.retry"
DEAD_QUEUE = "crawl.flats.tasks.dead"


def connect():
    params = pika.URLParameters(RABBITMQ_URL)
    params.heartbeat = HEARTBEAT
    params.blocked_connection_timeout = BLOCKED_CONNECTION_TIMEOUT
    return pika.BlockingConnection(params)


def declare(channel):
    channel.queue_declare(MAIN_QUEUE, durable=True, arguments={"x-max-priority": 10})
    channel.queue_declare(
        RETRY_QUEUE,
        durable=True,
        arguments={
            "x-message-ttl": 30_000,
            "x-dead-letter-exchange": "",
            "x-dead-letter-routing-key": MAIN_QUEUE,
        },
    )
    channel.queue_declare(DEAD_QUEUE, durable=True)


def queue_depth(channel, queue):
    result = channel.queue_declare(queue=queue, passive=True)
    return int(result.method.message_count or 0)


def publish(channel, queue, payload, *, priority=0, attempt=0):
    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    channel.basic_publish(
        exchange="",
        routing_key=queue,
        body=body,
        properties=pika.BasicProperties(
            delivery_mode=2,
            content_type="application/json",
            priority=priority,
            headers={"attempt": attempt},
        ),
        mandatory=True,
    )


def publish_task(channel, task):
    payload = dict(task)
    priority = int(payload.pop("priority", 0))
    payload.setdefault("queuedAt", int(time.time()))
    publish(channel, MAIN_QUEUE, payload, priority=priority)


def api_request(path, payload=None, timeout=60):
    if len(QUEUE_INTERNAL_KEY) < 16:
        raise RuntimeError("QUEUE_INTERNAL_KEY must be at least 16 characters")

    data = None
    method = "GET"
    headers = {
        "X-Queue-Key": QUEUE_INTERNAL_KEY,
        "User-Agent": "flat-finder-rabbit-worker/2.0",
    }

    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        method = "POST"
        headers["Content-Type"] = "application/json"

    request = urllib.request.Request(
        f"{TASK_API_URL}{path}",
        method=method,
        data=data,
        headers=headers,
    )

    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def dispatch_once(channel):
    pending = queue_depth(channel, MAIN_QUEUE) + queue_depth(channel, RETRY_QUEUE)
    if pending > 0:
        print(
            f"[queue:dispatcher] skipped new crawl, pending={pending}",
            flush=True,
        )
        return

    plan = api_request("/internal/queue-plan", timeout=30)
    tasks = plan.get("tasks") or []

    for task in tasks:
        publish_task(channel, task)

    print(f"[queue:dispatcher] queued {len(tasks)} granular tasks", flush=True)


def dispatch_forever():
    while True:
        try:
            connection = connect()
            channel = connection.channel()
            channel.confirm_delivery()
            declare(channel)
            dispatch_once(channel)
            connection.close()
        except Exception as exc:
            print(f"[queue:dispatcher] error: {exc}", flush=True)

        time.sleep(REFRESH_SECONDS)


def execute_task(payload):
    return api_request("/internal/queue-task", payload=payload, timeout=180)


def worker_forever():
    while True:
        try:
            connection = connect()
            channel = connection.channel()
            channel.confirm_delivery()
            declare(channel)
            channel.basic_qos(prefetch_count=PREFETCH)

            def on_message(ch, method, properties, body):
                try:
                    payload = json.loads(body.decode("utf-8"))
                    result = execute_task(payload)

                    # Publish page N+1 before acknowledging page N. If publishing
                    # fails, the current page goes through the normal retry path;
                    # persistence is idempotent, so this cannot lose the chain.
                    for next_task in result.get("nextTasks") or []:
                        publish_task(ch, next_task)

                    ch.basic_ack(method.delivery_tag)
                    print(
                        f"[queue:worker] completed {payload.get('type')} "
                        f"country={payload.get('country')} page={payload.get('page', '-')} "
                        f"fetched={result.get('fetched', 0)} "
                        f"next={len(result.get('nextTasks') or [])}",
                        flush=True,
                    )
                except Exception as exc:
                    attempt = int((properties.headers or {}).get("attempt", 0)) + 1
                    priority = int(properties.priority or 0)
                    try:
                        payload = json.loads(body.decode("utf-8"))
                    except Exception:
                        payload = {"raw": body.decode("utf-8", errors="replace")}

                    target = RETRY_QUEUE if attempt < MAX_ATTEMPTS else DEAD_QUEUE
                    publish(ch, target, payload, priority=priority, attempt=attempt)
                    ch.basic_ack(method.delivery_tag)
                    print(
                        f"[queue:worker] failed attempt={attempt} target={target}: {exc}",
                        flush=True,
                    )

            channel.basic_consume(MAIN_QUEUE, on_message_callback=on_message)
            print(
                f"[queue:worker] consuming granular tasks heartbeat={HEARTBEAT}s",
                flush=True,
            )
            channel.start_consuming()
        except Exception as exc:
            print(f"[queue:worker] connection error: {exc}", flush=True)
            time.sleep(5)


if __name__ == "__main__":
    if MODE == "dispatcher":
        dispatch_forever()
    else:
        worker_forever()