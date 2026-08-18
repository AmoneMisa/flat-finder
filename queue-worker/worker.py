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

MAIN_QUEUE = "crawl.flats.tasks"
RETRY_QUEUE = "crawl.flats.tasks.retry"
DEAD_QUEUE = "crawl.flats.tasks.dead"


def connect():
    params = pika.URLParameters(RABBITMQ_URL)
    params.heartbeat = 30
    params.blocked_connection_timeout = 60
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
    plan = api_request("/internal/queue-plan", timeout=30)
    tasks = plan.get("tasks") or []

    for task in tasks:
        priority = int(task.pop("priority", 0))
        task["queuedAt"] = int(time.time())
        publish(channel, MAIN_QUEUE, task, priority=priority)

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
            declare(channel)
            channel.basic_qos(prefetch_count=PREFETCH)

            def on_message(ch, method, properties, body):
                try:
                    payload = json.loads(body.decode("utf-8"))
                    result = execute_task(payload)
                    ch.basic_ack(method.delivery_tag)
                    print(
                        f"[queue:worker] completed {payload.get('type')} "
                        f"country={payload.get('country')} fetched={result.get('fetched', 0)}",
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
            print("[queue:worker] consuming granular tasks", flush=True)
            channel.start_consuming()
        except Exception as exc:
            print(f"[queue:worker] connection error: {exc}", flush=True)
            time.sleep(5)


if __name__ == "__main__":
    if MODE == "dispatcher":
        dispatch_forever()
    else:
        worker_forever()
