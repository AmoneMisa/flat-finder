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
QUEUE_PROTOCOL_VERSION = max(3, int(os.environ.get("QUEUE_PROTOCOL_VERSION", "3")))
QUEUE_SHARDS = max(1, int(os.environ.get("QUEUE_SHARDS", "2")))
QUEUE_SHARD = max(0, int(os.environ.get("QUEUE_SHARD", "0"))) % QUEUE_SHARDS
HEARTBEAT = max(60, int(os.environ.get("RABBITMQ_HEARTBEAT", "300")))
BLOCKED_CONNECTION_TIMEOUT = max(
    HEARTBEAT,
    int(os.environ.get("RABBITMQ_BLOCKED_CONNECTION_TIMEOUT", "360")),
)

MAIN_QUEUE_PREFIX = "crawl.flats.tasks.v3"
RETRY_QUEUE_PREFIX = "crawl.flats.tasks.v3.retry"
DEAD_QUEUE = "crawl.flats.tasks.dead"
LEGACY_MAIN_QUEUE = "crawl.flats.tasks"
LEGACY_RETRY_QUEUE = "crawl.flats.tasks.retry"


def main_queue(shard):
    return f"{MAIN_QUEUE_PREFIX}.{int(shard) % QUEUE_SHARDS}"


def retry_queue(shard):
    return f"{RETRY_QUEUE_PREFIX}.{int(shard) % QUEUE_SHARDS}"


def connect():
    params = pika.URLParameters(RABBITMQ_URL)
    params.heartbeat = HEARTBEAT
    params.blocked_connection_timeout = BLOCKED_CONNECTION_TIMEOUT
    return pika.BlockingConnection(params)


def declare(channel):
    for shard in range(QUEUE_SHARDS):
        channel.queue_declare(
            main_queue(shard),
            durable=True,
            arguments={"x-max-priority": 10},
        )
        channel.queue_declare(
            retry_queue(shard),
            durable=True,
            arguments={
                "x-message-ttl": 30_000,
                "x-dead-letter-exchange": "",
                "x-dead-letter-routing-key": main_queue(shard),
            },
        )
    channel.queue_declare(DEAD_QUEUE, durable=True)


def purge_legacy_queues(channel):
    # Re-declare the v2 queues with their original arguments so this is safe
    # whether the broker still has them or a fresh RabbitMQ volume is used.
    channel.queue_declare(
        LEGACY_MAIN_QUEUE,
        durable=True,
        arguments={"x-max-priority": 10},
    )
    channel.queue_declare(
        LEGACY_RETRY_QUEUE,
        durable=True,
        arguments={
            "x-message-ttl": 30_000,
            "x-dead-letter-exchange": "",
            "x-dead-letter-routing-key": LEGACY_MAIN_QUEUE,
        },
    )

    purged = 0
    for queue in (LEGACY_MAIN_QUEUE, LEGACY_RETRY_QUEUE):
        result = channel.queue_purge(queue=queue)
        purged += int(result.method.message_count or 0)

    if purged:
        print(f"[queue:dispatcher] purged {purged} legacy v2 tasks", flush=True)


def queue_depth(channel, queue):
    result = channel.queue_declare(queue=queue, passive=True)
    return int(result.method.message_count or 0)


def all_pending(channel):
    return sum(
        queue_depth(channel, main_queue(shard))
        + queue_depth(channel, retry_queue(shard))
        for shard in range(QUEUE_SHARDS)
    )


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


def task_shard(task):
    try:
        return int(task.get("crawlerShard") or 0) % QUEUE_SHARDS
    except (TypeError, ValueError):
        return 0


def publish_task(channel, task):
    payload = dict(task)
    priority = int(payload.pop("priority", 0))
    payload.setdefault("queuedAt", int(time.time()))
    shard = task_shard(payload)
    publish(channel, main_queue(shard), payload, priority=priority)


def api_request(path, payload=None, timeout=60):
    if len(QUEUE_INTERNAL_KEY) < 16:
        raise RuntimeError("QUEUE_INTERNAL_KEY must be at least 16 characters")

    data = None
    method = "GET"
    headers = {
        "X-Queue-Key": QUEUE_INTERNAL_KEY,
        "User-Agent": "flat-finder-rabbit-worker/3.0",
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
    pending = all_pending(channel)
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

    per_shard = [0] * QUEUE_SHARDS
    for task in tasks:
        per_shard[task_shard(task)] += 1

    print(
        f"[queue:dispatcher] queued {len(tasks)} tasks "
        f"generation={plan.get('crawlGeneration')} shards={per_shard}",
        flush=True,
    )
    return True


def dispatch_forever():
    legacy_cleaned = False
    while True:
        queued = False
        try:
            connection = connect()
            channel = connection.channel()
            channel.confirm_delivery()
            declare(channel)
            if not legacy_cleaned:
                purge_legacy_queues(channel)
                legacy_cleaned = True
            queued = dispatch_once(channel)
            connection.close()
        except Exception as exc:
            print(f"[queue:dispatcher] error: {exc}", flush=True)

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
        connection.process_data_events(time_limit=1)
    return future.result()


def handle_delivery(connection, channel, executor, method, properties, body):
    try:
        payload = json.loads(body.decode("utf-8"))
    except Exception:
        payload = {"raw": body.decode("utf-8", errors="replace")}

    protocol = task_protocol(payload)
    shard = task_shard(payload)

    if protocol != QUEUE_PROTOCOL_VERSION or shard != QUEUE_SHARD:
        channel.basic_ack(method.delivery_tag)
        print(
            f"[queue:worker:{QUEUE_SHARD}] dropped mismatched task "
            f"protocol={protocol} shard={shard} type={payload.get('type')} "
            f"country={payload.get('country')} page={payload.get('page', '-')}",
            flush=True,
        )
        return

    try:
        result = execute_with_heartbeats(connection, executor, payload)

        for next_task in result.get("nextTasks") or []:
            publish_task(channel, next_task)

        channel.basic_ack(method.delivery_tag)
        print(
            f"[queue:worker:{QUEUE_SHARD}] completed {payload.get('type')} "
            f"country={payload.get('country')} city={payload.get('citySlug') or 'all'} "
            f"page={payload.get('page', '-')} fetched={result.get('fetched', 0)} "
            f"dedup={1 if result.get('deduplicated') else 0} "
            f"next={len(result.get('nextTasks') or [])}",
            flush=True,
        )
    except Exception as exc:
        attempt = int((properties.headers or {}).get("attempt", 0)) + 1
        priority = int(properties.priority or 0)
        target = retry_queue(QUEUE_SHARD) if attempt < MAX_ATTEMPTS else DEAD_QUEUE
        publish(channel, target, payload, priority=priority, attempt=attempt)
        channel.basic_ack(method.delivery_tag)
        print(
            f"[queue:worker:{QUEUE_SHARD}] failed attempt={attempt} target={target}: {exc}",
            flush=True,
        )


def worker_forever():
    while True:
        executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix=f"queue-http-{QUEUE_SHARD}")
        try:
            connection = connect()
            channel = connection.channel()
            channel.confirm_delivery()
            declare(channel)
            channel.basic_qos(prefetch_count=PREFETCH)
            own_queue = main_queue(QUEUE_SHARD)
            print(
                f"[queue:worker:{QUEUE_SHARD}] consuming {own_queue} "
                f"heartbeat={HEARTBEAT}s protocol={QUEUE_PROTOCOL_VERSION}",
                flush=True,
            )

            while connection.is_open and channel.is_open:
                method, properties, body = channel.basic_get(
                    queue=own_queue,
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
            print(f"[queue:worker:{QUEUE_SHARD}] connection error: {exc}", flush=True)
            time.sleep(5)
        finally:
            executor.shutdown(wait=True, cancel_futures=True)


if __name__ == "__main__":
    if MODE == "dispatcher":
        dispatch_forever()
    else:
        worker_forever()
