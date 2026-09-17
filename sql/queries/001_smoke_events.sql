INSERT INTO saas_analytics.events
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
    event_id,
    tenant_id,
    user_id,
    event_type,
    service_name,
    region,
    status_code,
    duration_ms,
    deployment_version,
    parseDateTime64BestEffort(event_timestamp, 3, 'UTC'),
    payload
FROM VALUES
(
    'event_id UUID,
     tenant_id UInt32,
     user_id UInt64,
     event_type String,
     service_name String,
     region String,
     status_code UInt16,
     duration_ms UInt32,
     deployment_version String,
     event_timestamp String,
     payload String',

    (
        '00000000-0000-4000-8000-000000000001',
        101,
        1001,
        'api_request',
        'api',
        'eu-central-1',
        200,
        84,
        'v1.0.0',
        '2026-09-17 14:45:00.100',
        '{"path":"/api/orders","method":"GET"}'
    ),
    (
        '00000000-0000-4000-8000-000000000002',
        101,
        1002,
        'api_request',
        'api',
        'eu-central-1',
        500,
        932,
        'v1.0.0',
        '2026-09-17 14:45:01.200',
        '{"path":"/api/orders","method":"POST"}'
    ),
    (
        '00000000-0000-4000-8000-000000000003',
        101,
        1003,
        'login',
        'auth',
        'eu-central-1',
        200,
        121,
        'v1.0.0',
        '2026-09-17 14:45:02.300',
        '{"provider":"password"}'
    ),
    (
        '00000000-0000-4000-8000-000000000004',
        102,
        2001,
        'payment_processed',
        'billing',
        'eu-west-1',
        200,
        245,
        'v1.0.1',
        '2026-09-17 14:45:03.400',
        '{"currency":"USD","amount":49.99}'
    ),
    (
        '00000000-0000-4000-8000-000000000005',
        102,
        2002,
        'payment_failed',
        'billing',
        'eu-west-1',
        503,
        1502,
        'v1.0.1',
        '2026-09-17 14:45:04.500',
        '{"currency":"USD","reason":"upstream_timeout"}'
    ),
    (
        '00000000-0000-4000-8000-000000000006',
        102,
        2003,
        'job_completed',
        'worker',
        'eu-west-1',
        200,
        320,
        'v1.0.1',
        '2026-09-17 14:45:05.600',
        '{"job":"invoice_generation"}'
    ),
    (
        '00000000-0000-4000-8000-000000000007',
        103,
        3001,
        'api_request',
        'api',
        'us-east-1',
        429,
        43,
        'v1.1.0',
        '2026-09-17 14:45:06.700',
        '{"path":"/api/search","method":"GET"}'
    ),
    (
        '00000000-0000-4000-8000-000000000008',
        103,
        3002,
        'login_failed',
        'auth',
        'us-east-1',
        401,
        72,
        'v1.1.0',
        '2026-09-17 14:45:07.800',
        '{"provider":"password","reason":"invalid_credentials"}'
    )
) AS smoke
WHERE event_id NOT IN
(
    SELECT event_id
    FROM saas_analytics.events
    WHERE event_id IN
    (
        toUUID('00000000-0000-4000-8000-000000000001'),
        toUUID('00000000-0000-4000-8000-000000000002'),
        toUUID('00000000-0000-4000-8000-000000000003'),
        toUUID('00000000-0000-4000-8000-000000000004'),
        toUUID('00000000-0000-4000-8000-000000000005'),
        toUUID('00000000-0000-4000-8000-000000000006'),
        toUUID('00000000-0000-4000-8000-000000000007'),
        toUUID('00000000-0000-4000-8000-000000000008')
    )
);