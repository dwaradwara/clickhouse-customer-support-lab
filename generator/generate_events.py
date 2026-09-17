import argparse
import json
import random
import sys
import time
import uuid
from datetime import datetime, timedelta, timezone

from confluent_kafka import Producer


EVENT_TYPES = [
    ("api_request", "api"),
    ("login", "auth"),
    ("login_failed", "auth"),
    ("payment_processed", "billing"),
    ("payment_failed", "billing"),
    ("job_completed", "worker"),
]

REGIONS = [
    "eu-central-1",
    "eu-west-1",
    "us-east-1",
]

VERSIONS = [
    "v1.2.0",
    "v1.2.1",
    "v1.3.0",
]


def parse_start_time(value: str | None) -> datetime:
    if value is None:
        return datetime.now(timezone.utc)

    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))

    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)

    return parsed.astimezone(timezone.utc)


def build_event(
    rng: random.Random,
    event_number: int,
    start_time: datetime,
) -> dict:
    event_type, service_name = rng.choice(EVENT_TYPES)

    if event_type == "login_failed":
        status_code = 401

    elif event_type == "payment_failed":
        status_code = 503

    elif event_type == "api_request":
        status_code = rng.choices(
            [200, 400, 429, 500],
            weights=[85, 5, 5, 5],
            k=1,
        )[0]

    else:
        status_code = 200

    duration_ms = rng.randint(20, 1800)

    event_timestamp = start_time + timedelta(
        milliseconds=event_number
    )

    payload = {
        "source": "synthetic-generator",
        "scenario": event_type,
    }

    return {
        "event_id": str(
            uuid.UUID(
                int=rng.getrandbits(128),
                version=4,
            )
        ),
        "tenant_id": rng.randint(1, 100),
        "user_id": rng.randint(1, 1_000_000),
        "event_type": event_type,
        "service_name": service_name,
        "region": rng.choice(REGIONS),
        "status_code": status_code,
        "duration_ms": duration_ms,
        "deployment_version": rng.choice(VERSIONS),
        "event_timestamp": event_timestamp.strftime(
            "%Y-%m-%d %H:%M:%S.%f"
        )[:-3],
        "payload": json.dumps(
            payload,
            separators=(",", ":"),
        ),
    }


def serialize_event(event: dict) -> str:
    return json.dumps(
        event,
        separators=(",", ":"),
    )


def output_to_stdout(
    rng: random.Random,
    count: int,
    start_time: datetime,
) -> None:
    for event_number in range(count):
        event = build_event(
            rng=rng,
            event_number=event_number,
            start_time=start_time,
        )

        print(serialize_event(event))


def output_to_kafka(
    rng: random.Random,
    count: int,
    start_time: datetime,
    bootstrap_server: str,
    topic: str,
) -> None:
    producer = Producer(
        {
            "bootstrap.servers": bootstrap_server,
            "client.id": "clickhouse-support-lab-generator",
            "acks": "all",
        }
    )

    delivered = 0
    failed = 0

    def delivery_report(error, message) -> None:
        nonlocal delivered, failed

        if error is not None:
            failed += 1
            print(
                f"Delivery failed: {error}",
                file=sys.stderr,
            )
        else:
            delivered += 1

    started_at = time.perf_counter()

    for event_number in range(count):
        event = build_event(
            rng=rng,
            event_number=event_number,
            start_time=start_time,
        )

        value = serialize_event(event)

        producer.produce(
            topic=topic,
            key=str(event["tenant_id"]),
            value=value,
            callback=delivery_report,
        )

        producer.poll(0)

    remaining = producer.flush(30)

    elapsed = time.perf_counter() - started_at

    if remaining != 0:
        raise RuntimeError(
            f"{remaining} Kafka message(s) remained undelivered"
        )

    events_per_second = (
        delivered / elapsed
        if elapsed > 0
        else 0
    )

    print(
        (
            f"Generated={count} "
            f"Delivered={delivered} "
            f"Failed={failed} "
            f"ElapsedSeconds={elapsed:.3f} "
            f"EventsPerSecond={events_per_second:.2f}"
        ),
        file=sys.stderr,
    )

    if failed > 0:
        raise RuntimeError(
            f"{failed} Kafka message(s) failed delivery"
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Generate synthetic SaaS events for the "
            "ClickHouse Customer Support Engineering Lab."
        )
    )

    parser.add_argument(
        "--count",
        type=int,
        default=1,
        help="Number of events to generate.",
    )

    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for reproducible event generation.",
    )

    parser.add_argument(
        "--start-time",
        help=(
            "UTC start time. Example: "
            "2026-09-17T16:00:00Z"
        ),
    )

    parser.add_argument(
        "--mode",
        choices=["stdout", "kafka"],
        default="stdout",
        help="Output destination.",
    )

    parser.add_argument(
        "--bootstrap-server",
        default="localhost:9092",
        help="Kafka bootstrap server used in kafka mode.",
    )

    parser.add_argument(
        "--topic",
        default="saas-events",
        help="Kafka topic used in kafka mode.",
    )

    args = parser.parse_args()

    if args.count < 1:
        raise SystemExit("--count must be at least 1")

    rng = random.Random(args.seed)
    start_time = parse_start_time(args.start_time)

    if args.mode == "stdout":
        output_to_stdout(
            rng=rng,
            count=args.count,
            start_time=start_time,
        )

    else:
        output_to_kafka(
            rng=rng,
            count=args.count,
            start_time=start_time,
            bootstrap_server=args.bootstrap_server,
            topic=args.topic,
        )


if __name__ == "__main__":
    main()