import json
import os
import time
import urllib.parse
import urllib.request

import pika

RABBITMQ_URL = os.environ.get("RABBITMQ_URL", "amqp://crawler:crawler@flat-finder-rabbitmq:5672/%2F")
BACKEND_URL = os.environ.get("FLAT_BACKEND_URL", "http://flat-finder-backend:4000").rstrip("/")
MODE = os.environ.get("QUEUE_MODE", "worker").strip().lower()
REFRESH_SECONDS = max(60, int(os.environ.get("QUEUE_REFRESH_SECONDS", "1800")))
PREFETCH = max(1, int(os.environ.get("QUEUE_PREFETCH", "1")))
MAX_ATTEMPTS = max(1, int(os.environ.get("QUEUE_MAX_ATTEMPTS", "5")))

MAIN_QUEUE = "crawl.flats.refresh"
RETRY_QUEUE = "crawl.flats.refresh.retry"
DEAD_QUEUE = "crawl.flats.refresh.dead"

COUNTRIES = [
    ("UA", 10),
    ("RO", 5),
    ("KZ", 5),
    ("UZ", 5),
]


def connect():
    params = pika.URLParameters(RABBITMQ_URL)
    params.heartbeat = 30
    params.blocked_connection_timeout = 60
    return pika.BlockingConnection(params)


def declare(channel):
    channel.queue_declare(
        MAIN_QUEUE,
        durable=True,
        arguments={"x-max-priority": 10},
    )
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


def dispatch_forever():
    while True:
        try:
            connection = connect()
            channel = connection.channel()
            channel.confirm_delivery()
            declare(channel)

            for country, priority in COUNTRIES:
                publish(
                    channel,
                    MAIN_QUEUE,
                    {
                        "type": "flat.refresh.country",
                        "country": country,
                        "queuedAt": int(time.time()),
                    },
                    priority=priority,
                )

            print("[queue:dispatcher] queued country refreshes", flush=True)
            connection.close()
        except Exception as exc:
            print(f"[queue:dispatcher] error: {exc}", flush=True)

        time.sleep(REFRESH_SECONDS)


def execute_task(payload):
    if payload.get("type") != "flat.refresh.country":
        raise ValueError(f"unsupported task type {payload.get('type')!r}")

    country = str(payload.get("country") or "").upper()
    if country not in {code for code, _ in COUNTRIES}:
        raise ValueError(f"unsupported country {country!r}")

    query = urllib.parse.urlencode(
        {
            "countries": country,
            "refresh": "1",
            "limit": "1",
        }
    )

    request = urllib.request.Request(
        f"{BACKEND_URL}/api/listings?{query}",
        headers={"User-Agent": "flat-finder-rabbit-worker/1.0"},
    )

    with urllib.request.urlopen(request, timeout=300) as response:
        if response.status < 200 or response.status >= 300:
            raise RuntimeError(f"backend HTTP {response.status}")
        response.read(1)


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
                    execute_task(payload)
                    ch.basic_ack(method.delivery_tag)
                    print(
                        f"[queue:worker] completed {payload.get('country')}",
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
                    publish(
                        ch,
                        target,
                        payload,
                        priority=priority,
                        attempt=attempt,
                    )
                    ch.basic_ack(method.delivery_tag)
                    print(
                        f"[queue:worker] failed attempt={attempt} target={target}: {exc}",
                        flush=True,
                    )

            channel.basic_consume(MAIN_QUEUE, on_message_callback=on_message)
            print("[queue:worker] consuming", flush=True)
            channel.start_consuming()
        except Exception as exc:
            print(f"[queue:worker] connection error: {exc}", flush=True)
            time.sleep(5)


if __name__ == "__main__":
    if MODE == "dispatcher":
        dispatch_forever()
    else:
        worker_forever()
