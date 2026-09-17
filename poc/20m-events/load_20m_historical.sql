TRUNCATE TABLE query_benchmark.events_bad_order;
INSERT INTO query_benchmark.events_bad_order
(
    event_id,
    tenant_id,
    user_id,
    event_type,
    service_name,
    region,
    status_code,
    duration_ms,
    deployment_version,
    event_timestamp,
    payload
)
SELECT
    toUUID(
        concat(
            '00000000-0000-4000-8000-',
            leftPad(toString(number), 12, '0')
        )
    ) AS event_id,

    toUInt32((number % 1000) + 1) AS tenant_id,

    toUInt64((number % 1000000) + 1) AS user_id,

    multiIf(
        number % 6 = 0, 'api_request',
        number % 6 = 1, 'login',
        number % 6 = 2, 'login_failed',
        number % 6 = 3, 'payment_processed',
        number % 6 = 4, 'payment_failed',
        'job_completed'
    ) AS event_type,

    multiIf(
        number % 6 = 0, 'api',
        number % 6 IN (1, 2), 'auth',
        number % 6 IN (3, 4), 'billing',
        'worker'
    ) AS service_name,

    multiIf(
        number % 3 = 0, 'eu-central-1',
        number % 3 = 1, 'eu-west-1',
        'us-east-1'
    ) AS region,

    toUInt16(
        multiIf(
            number % 6 = 2, 401,
            number % 6 = 4, 503,
            number % 100 = 0, 500,
            number % 100 = 1, 429,
            200
        )
    ) AS status_code,

    toUInt32((number * 37) % 1800 + 20) AS duration_ms,

    multiIf(
        number % 3 = 0, 'v1.2.0',
        number % 3 = 1, 'v1.2.1',
        'v1.3.0'
    ) AS deployment_version,

    toDateTime64(
        '2026-01-01 00:00:00.000',
        3,
        'UTC'
    ) + toIntervalMillisecond(number * 400) AS event_timestamp,

    concat(
        '{"source":"historical-benchmark","sequence":',
        toString(number),
        '}'
    ) AS payload

FROM numbers_mt(20000000);