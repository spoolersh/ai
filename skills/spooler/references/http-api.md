# Spooler HTTP API reference

The operation pages at https://docs.spooler.sh/operations/<operationId>
are the contract; the spec is https://docs.spooler.sh/openapi.json. This
file is the same facts in one place for an agent that is writing requests.

Base URL: `https://api.spooler.sh/v1` (local image: `http://localhost:8080/v1`).
Every request: `Authorization: Bearer <key>`. Every path starts with
`/spools/{spool}`; every account has a spool named `default`.

Name rule (spool, queue): 1-63 bytes of `A-Za-z0-9_:-`.

## Operations

| operationId | Method and path | Request | Success |
| --- | --- | --- | --- |
| `spool` | `GET /spools/{spool}` | | `200` Spool JSON |
| `spoolQueues` | `GET /spools/{spool}/queues` | query `limit` 1-1000 (default 100), `after` cursor, `match` RE2 | `200` `{items:[Queue], next?}` |
| `spoolQueue` | `GET /spools/{spool}/queues/{queue}` | | `200` Queue JSON |
| `createQueue` | `PUT /spools/{spool}/queues/{queue}` | optional JSON body `QueueSettingsCreate` | `201` Queue JSON |
| `updateQueue` | `PATCH /spools/{spool}/queues/{queue}` | query `uid` optional; JSON body `QueueSettingsUpdate`, at least one field | `204` |
| `deleteQueue` | `DELETE /spools/{spool}/queues/{queue}` | query `mode=force\|drain` required, `uid` optional | `204` deleted, `202` in progress |
| `queueMessages` | `GET /spools/{spool}/queues/{queue}/messages` | query `state`, `limit` 1-1000, `after`, `handle=true` | `200` `{items:[Message], next?}` |
| `sendMessage` | `POST /spools/{spool}/queues/{queue}/send` | body = raw payload; query `handle=true`; headers `Spooler-Delay-Seconds`, `Spooler-Dedup-String` or `Spooler-Dedup-Hash` | `201` + `Spooler-Message-Id` (+ `Spooler-Handle`); `200` on a dedup hit |
| `recvMessage` | `POST /spools/{spool}/queues/{queue}/recv` | query `waitSeconds` 0-20 | `200` body = payload + lease headers; `204` nothing |
| `ackMessage` | `POST /spools/{spool}/ack` | header `Spooler-Lease` | `204` |
| `nackMessage` | `POST /spools/{spool}/nack` | header `Spooler-Lease` | `204` |
| `releaseMessage` | `POST /spools/{spool}/release` | headers `Spooler-Lease`, `Spooler-Delay-Seconds` optional | `204` |
| `failMessage` | `POST /spools/{spool}/fail` | header `Spooler-Lease` | `204` |
| `renewLease` | `POST /spools/{spool}/renew` | header `Spooler-Lease` | `204` + `Spooler-Lease-Expires-At` (absent when no timeout) |
| `ackAndSend` | `POST /spools/{spool}/ack-and-send` | body = new payload; headers `Spooler-Lease`, `Spooler-Queue` required; `Spooler-Delay-Seconds`, dedup headers optional; query `handle=true` | `201` + `Spooler-Message-Id` |
| `inspectMessage` | `POST /spools/{spool}/inspect` | header `Spooler-Handle` | `200` body = payload + attribute headers |
| `recoverFailure` | `POST /spools/{spool}/recover` | headers `Spooler-Handle`, `Spooler-Delay-Seconds` optional | `204` |
| `discardMessage` | `POST /spools/{spool}/discard` | exactly one of `Spooler-Lease`, `Spooler-Handle` | `204` |

Settle operations take no body. Every operation accepts only the
`Spooler-*` request headers listed for it; any other answers `400`
`unknown_header`.

## Response headers on a receive

```http
HTTP/2 200
spooler-lease: <opaque>
spooler-message-id: 1-1
spooler-message-retries: 0
spooler-message-created-at: 2026-08-12T10:00:00Z
spooler-lease-expires-at: 2026-08-12T10:05:00Z

<payload bytes>
```

`spooler-lease-expires-at` is absent on a queue whose `leaseTimeoutSeconds`
is 0. An inspect answers the same attribute headers plus
`Spooler-Message-State`, `Spooler-Message-Visible-At` (delayed only) and
`Spooler-Message-Expires-At` (when retention is on).

## curl examples

Variables as in the quickstart:

```sh
export SPOOLER_KEY='<your api key>'
export SPOOLER_API=https://api.spooler.sh/v1   # local: http://localhost:8080/v1
```

Create a queue with settings:

```sh
curl -X PUT "$SPOOLER_API/spools/default/queues/orders" \
  -H "Authorization: Bearer $SPOOLER_KEY" \
  -H "Content-Type: application/json" \
  --data '{"leaseTimeoutSeconds":120,"maxRetries":5,"dedupWindowSeconds":60}'
```

Send with a dedup key and a delay, asking for a handle:

```sh
curl -si -X POST "$SPOOLER_API/spools/default/queues/orders/send?handle=true" \
  -H "Authorization: Bearer $SPOOLER_KEY" \
  -H "Spooler-Dedup-String: order-42-created" \
  -H "Spooler-Delay-Seconds: 60" \
  --data-binary @payload.bin
```

Send from a file without a shell expanding it: `--data-binary @file`. An
empty body sends an empty message. Do not set `Content-Type`; the server
stores bytes.

Receive, long-polling up to 20 seconds:

```sh
curl -si -X POST "$SPOOLER_API/spools/default/queues/orders/recv?waitSeconds=20" \
  -H "Authorization: Bearer $SPOOLER_KEY"
```

Save headers and body apart: `curl -s -D headers.txt -o payload.bin ...`,
then read the lease with `grep -i '^spooler-lease:' headers.txt`.

Settle (ack, nack, release, fail, renew: same shape, different path):

```sh
curl -X POST "$SPOOLER_API/spools/default/nack" \
  -H "Authorization: Bearer $SPOOLER_KEY" \
  -H "Spooler-Lease: $LEASE"
```

Release with a backoff:

```sh
curl -X POST "$SPOOLER_API/spools/default/release" \
  -H "Authorization: Bearer $SPOOLER_KEY" \
  -H "Spooler-Lease: $LEASE" \
  -H "Spooler-Delay-Seconds: 30"
```

Ack-and-send to the next stage:

```sh
curl -si -X POST "$SPOOLER_API/spools/default/ack-and-send" \
  -H "Authorization: Bearer $SPOOLER_KEY" \
  -H "Spooler-Lease: $LEASE" \
  -H "Spooler-Queue: next-stage" \
  --data-binary 'next payload'
```

List failed messages with handles:

```sh
curl -s "$SPOOLER_API/spools/default/queues/orders/messages?state=failed&handle=true" \
  -H "Authorization: Bearer $SPOOLER_KEY"
```

```json
{"items":[{"id":"1-17","state":"failed","retries":5,"createdAt":"2026-08-12T10:00:00Z","expiresAt":"2026-08-19T10:00:00Z","handle":"<opaque>"}]}
```

Pass `next` back as `after=` until it is absent.

Inspect, recover, discard by handle:

```sh
curl -s -X POST "$SPOOLER_API/spools/default/inspect" \
  -H "Authorization: Bearer $SPOOLER_KEY" \
  -H "Spooler-Handle: $HANDLE"

curl -X POST "$SPOOLER_API/spools/default/recover" \
  -H "Authorization: Bearer $SPOOLER_KEY" \
  -H "Spooler-Handle: $HANDLE"

curl -X POST "$SPOOLER_API/spools/default/discard" \
  -H "Authorization: Bearer $SPOOLER_KEY" \
  -H "Spooler-Handle: $HANDLE"
```

Update settings only if the queue is still the one you read (`uid` from
the Queue JSON):

```sh
curl -X PATCH "$SPOOLER_API/spools/default/queues/orders?uid=$UID" \
  -H "Authorization: Bearer $SPOOLER_KEY" \
  -H "Content-Type: application/json" \
  --data '{"maxRetries":3}'
```

Delete, mode required:

```sh
curl -X DELETE "$SPOOLER_API/spools/default/queues/orders?mode=drain" \
  -H "Authorization: Bearer $SPOOLER_KEY"
```

Spool stats:

```sh
curl -s "$SPOOLER_API/spools/default" -H "Authorization: Bearer $SPOOLER_KEY"
```

## JSON shapes

Queue:

```json
{
  "name": "orders",
  "uid": "<opaque>",
  "createdAt": "2026-08-12T10:00:00Z",
  "state": "active",
  "settings": {
    "leaseTimeoutSeconds": 300,
    "maxRetries": 10,
    "dedupWindowSeconds": 0,
    "retentionSeconds": 604800,
    "effectiveRetentionSeconds": 604800,
    "recvRateLimit": {"intervalMicros": 0, "burst": 0}
  },
  "stats": { "...": "MessageStats" }
}
```

Queue `state`: `active`, `draining` (refuses sends, deleted once empty;
failed messages block the drain), `deleting`.

MessageStats: `sampledAt`, `startedAt`, current counts `total`, `dataBytes`,
`delayed`, `visible`, `pending`, `failed`, `unavailable`, and cumulative
`addedTotal`, `ackedTotal`, `nackedTotal`, `releasedTotal`, `failedTotal`,
`discardedTotal`, `expiredTotal`. Cumulative counters restart at
`startedAt`; compute rates only between samples with equal `startedAt`.

Message (listing entry): `id`, `state`, `retries`, `createdAt`, and when
applicable `visibleAt`, `leaseExpiresAt`, `expiresAt`, `handle`.

Message `state`: `delayed`, `visible`, `pending` (leased), `failed`,
`unavailable` (payload load failing, retried by the server; not yours to
act on).

Error:

```json
{"kind":"queue_not_found","message":"queue orders does not exist","details":{"queue":"orders"}}
```

`details` per kind: `queue_not_found` `{queue}`, `queue_limit` `{max}`,
`retention_limit` `{maxSeconds}`, `spool_full` `{limit: messages|dataBytes, max}`,
`dedup_claimed` `{id}`, `unknown_header` `{header}`, `queue_replaced` `{uid}`.
A `429` carries `Retry-After` in whole seconds, not repeated in the body.

## Dedup fingerprint recipe

`Spooler-Dedup-Hash` is `hex(sha256(key)[:16])`, 32 hex characters. A
sender using `Spooler-Dedup-String: key` and one sending that hash
deduplicate against each other. Never send both headers on one request.
