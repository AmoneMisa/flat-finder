import json
import os
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

import pika

RABBITMQ_URL = os.environ.get("RABBITMQ_URL", "amqp://crawler:crawler@flat-finder-rabbitmq:5672/%2F")
TASK_API_URL = os.environ.get("QUEUE_TASK_API_URL", "http://flat-finder-queue-task-api:4010").rstrip("/")
QUEUE_INTERNAL_KEY = os.environ.get("QUEUE_INTERNAL_KEY", "")
MODE = os.environ.get("QUEUE_MODE", "worker").strip().lower()
REFRESH_SECONDS = max(60, int(os.environ.get("QUEUE_REFRESH_SECONDS", "1800")))
PREFETCH = max(1, int(os.environ.get("QUEUE_PREFETCH", "1")))
MAX_ATTEMPTS = max(1, int(os.environ.get("QUEUE_MAX_ATTEMPTS", "5")))
QUEUE_PROTOCOL_VERSION = max(1, int(os.environ.get("QUEUE_PROTOCOL_VERSION", "2")))
# The broker may negotiate a heartbeat lower than the client proposal. Do not
# rely on a large heartbeat to survive slow HTTP work: worker_forever pumps AMQP
# I/O while the task API call runs in a helper thread.
HEARTBEAT = max(60, int(os.environ.get("RABBITMQ_HEARTBEAT", "300")))
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
        return False

    plan = api_request("/internal/queue-plan", timeout=30)
    tasks = plan.get("tasks") or []

    for task in tasks:
        publish_task(channel, task)

    print(f"[queue:dispatcher] queued {len(tasks)} granular tasks", flush=True)
    return True


def dispatch_forever():
    while True:
        queued = False
        try:
            connection = connect()
            channel = connection.channel()
            channel.confirm_delivery()
            declare(channel)
            queued = dispatch_once(channel)
            connection.close()
        except Exception as exc:
            print(f"[queue:dispatcher] error: {exc}", flush=True)

        # While an old/backlogged crawl is draining, re-check quickly instead of
        # waiting a full 30-minute refresh interval before seeding a clean crawl.
        time.sleep(REFRESH_SECONDS if queued else min(30, REFRESH_SECONDS))


def execute_task(payload):
    return api_request("/internal/queue-task", payload=payload, timeout=180)


def task_protocol(payload):
    try:
        return int(payload.get("queueProtocol") or 0)
    except (TypeError, ValueError):
        return 0


def execute_with_heartbeats(connection, executor, payload):
    future = executor.submit(execute_task, payload)
    while not future.done():
        # BlockingConnection only sends/receives heartbeat frames while its I/O
        # loop is serviced. Keep pumping it while urllib runs in another thread.
        connection.process_data_events(time_limit=1)
    return future.result()


def handle_delivery(connection, channel, executor, method, properties, body):
    try:
        payload = json.loads(body.decode("utf-8"))
    except Exception:
        payload = {"raw": body.decode("utf-8", errors="replace")}

    # RabbitMQ is durable across deploys, so the previous fixed-page plan can
    # leave thousands of now-invalid page tasks behind. Drop only messages from
    # older queue protocols; the dispatcher will seed a fresh versioned crawl as
    # soon as the backlog reaches zero.
    if task_protocol(payload) != QUEUE_PROTOCOL_VERSION:
        channel.basic_ack(method.delivery_tag)
        print(
            f"[queue:worker] dropped legacy task protocol={task_protocol(payload)} "
            f"type={payload.get('type')} country={payload.get('country')} "
            f"page={payload.get('page', '-')}",
            flush=True,
        )
        return

    try:
        result = execute_with_heartbeats(connection, executor, payload)

        # Publish page N+1 before acknowledging page N. If publishing fails, the
        # current page stays unacked and RabbitMQ safely redelivers it.
        for next_task in result.get("nextTasks") or []:
            publish_task(channel, next_task)

        channel.basic_ack(method.delivery_tag)
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
        target = RETRY_QUEUE if attempt < MAX_ATTEMPTS else DEAD_QUEUE
        publish(channel, target, payload, priority=priority, attempt=attempt)
        channel.basic_ack(method.delivery_tag)
        print(
            f"[queue:worker] failed attempt={attempt} target={target}: {exc}",
            flush=True,
        )


def worker_forever():
    while True:
        executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="queue-http")
        try:
            connection = connect()
            channel = connection.channel()
            channel.confirm_delivery()
            declare(channel)
            channel.basic_qos(prefetch_count=PREFETCH)
            print(
                f"[queue:worker] consuming granular tasks heartbeat={HEARTBEAT}s "
                f"protocol={QUEUE_PROTOCOL_VERSION}",
                flush=True,
            )

            # basic_get keeps delivery handling outside a pika callback. That is
            # important: process_data_events() is then safe to call while a task
            # is running, so even a broker-negotiated 30s heartbeat stays alive.
            while connection.is_open and channel.is_open:
                method, properties, body = channel.basic_get(
                    queue=MAIN_QUEUE,
                    auto_ack=False,
                )
                if method is None:
                    connection.process_data_events(time_limit=1)
                    continue

                handle_delivery(
                    connection,
                    channel,
                    executor,
                    method,
                    properties,
                    body,
                )
        except Exception as exc:
            print(f"[queue:worker] connection error: {exc}", flush=True)
            time.sleep(5)
        finally:
            executor.shutdown(wait=True, cancel_futures=True)


if __name__ == "__main__":
    if MODE == "dispatcher":
        dispatch_forever()
    else:
        worker_forever()