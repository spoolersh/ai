---
name: spooler
description: Use the Spooler message queue (spooler.sh) over HTTP with curl or any HTTP client. Explains at-least-once delivery, leases, the settles (ack, nack, release, fail, discard, ack-and-send), renew, dedup keys for safe retries, delayed sends, failed-message triage, queue settings, plan limits, error kinds and the spoolersh/memspoold local image. Use when a task mentions Spooler, spooler.sh, memspoold, api.spooler.sh, Spooler-Lease or Spooler-Handle headers, or needs a background job or work queue. For Go code use the spooler-go skill; for shell scripts the spooler-cli skill.
metadata:
  author: spoolersh
  version: "1.0.0"
  docs: https://docs.spooler.sh
---

# Spooler

Spooler is a message queue: bytes go in, are delivered at least once to
one receiver at a time, and leave once acknowledged. A receive leases a
message; the consumer settles the lease with ack, nack, release, fail or
discard. Messages that exhaust their retries are failed, a state of the
same message, not a separate queue. Use it for background jobs, work
shared by a pool of workers, webhook delivery and retries. It is not a
stream processor (no replay, no offsets), not pub/sub (no fan-out), not a
workflow engine, and not FIFO.

The contract is https://docs.spooler.sh: `/delivery` (guarantees),
`/dedup`, `/errors`, `/limits`, `/local`, `/api` and one page per
operation at `/operations/<operationId>`. Read those for anything this
file does not state; never guess server behaviour.

## Setup

This skill covers the HTTP API, which every client speaks. Two sibling
skills cover the clients: `spooler-go` (module
`github.com/spoolersh/spooler-go`) and `spooler-cli` (the `spooler`
binary). The rules below hold for all three.

Base URL `https://api.spooler.sh/v1`, API key from
https://console.spooler.sh as `Authorization: Bearer <key>`. Every
operation and its curl sample is in `references/http-api.md`.

For development and tests run the local image, free for development and
testing, which serves the same API in memory with no account:

```sh
docker run --rm -p 127.0.0.1:8080:8080 spoolersh/memspoold
export SPOOLER_API=http://localhost:8080/v1   # hosted: https://api.spooler.sh/v1
export SPOOLER_KEY=local                      # any value authenticates locally
```

It persists nothing, has one spool `default`, never rate-limits and never
answers `402`, `429` or `503`. Every account has a spool named `default`;
queues live in spools.

## The loop

```sh
curl -X PUT "$SPOOLER_API/spools/default/queues/jobs" \
  -H "Authorization: Bearer $SPOOLER_KEY"                      # 201, queue JSON

curl -si -X POST "$SPOOLER_API/spools/default/queues/jobs/send" \
  -H "Authorization: Bearer $SPOOLER_KEY" \
  --data-binary 'hello'                                        # 201, spooler-message-id

curl -si -X POST "$SPOOLER_API/spools/default/queues/jobs/recv?waitSeconds=20" \
  -H "Authorization: Bearer $SPOOLER_KEY"                      # 200 body=payload, spooler-lease; 204 nothing

curl -X POST "$SPOOLER_API/spools/default/ack" \
  -H "Authorization: Bearer $SPOOLER_KEY" \
  -H "Spooler-Lease: <spooler-lease header value>"             # 204
```

The payload is the raw request or response body, no envelope, no base64;
attributes travel as `Spooler-*` headers. Queue management is JSON.

## Rules

1. **Receiving does not delete.** It leases. Settle every delivery, or the
   lease times out (`leaseTimeoutSeconds`, default 300) and the message is
   redelivered with `retries` incremented. A queue with timeout 0 holds a
   lease until settled or a primary change.
2. **Pick the right settle.** `ack`: done, remove. `nack`: failed, retry
   later, counts a retry; after `maxRetries` (default 10) the message is
   failed. `release`: not the message's fault (shutdown, wrong worker),
   redeliver without counting a retry, optional `Spooler-Delay-Seconds`
   backoff. `fail`: poison, mark failed now for a human. `discard`: drop
   for good. `ack-and-send`: ack this and append the next stage's message
   atomically (`Spooler-Queue` names the destination). A handler that
   releases on every error retries forever; nack is the error path.
3. **Handlers must be idempotent.** Delivery is at least once: a lease
   expiry, a crash before ack, a lost ack response or a primary change
   repeats a delivery. Dedupe on your side by effect or by message id.
4. **Not FIFO.** Oldest visible first, approximately; delays, redeliveries
   and concurrent consumers reorder. Put ordered work in one message.
5. **Tokens are opaque and typed.** A lease (from receive) settles and
   renews; a handle (from `send?handle=true` or a listing with
   `handle=true`) inspects, recovers and discards. Neither is accepted for
   the other. Never decode, compare or build one. Ids never act: no
   operation takes a message id.
6. **Renew is a reset, not an extension.** Long work renews on a schedule
   shorter than the lease timeout and keeps the same lease. A `410`
   `stale_token` on renew means the message was discarded or the lease is
   gone: stop the work. Nothing to renew when `Spooler-Lease-Expires-At`
   is absent.
7. **Retry sends only with a dedup key.** Every `4xx`, `503` and `507`
   changed nothing and may be retried as the kind allows. A `500`, `502`,
   `504` or no response may have appended: retry a send only on a queue
   with `dedupWindowSeconds > 0`, with the same `Spooler-Dedup-String`
   the first attempt carried, inside the window. Assign the key before the
   first attempt. A repeat answers `200` with the original id instead of
   `201`. A key on a queue without a window is refused, `400`
   `dedup_disabled`. Settles and ack-and-send retry safely: a committed one
   answers `410`.
8. **Headers are strict.** Each operation accepts only its own `Spooler-*`
   request headers; anything else is `400` `unknown_header`. Keys never go
   in query strings. Durations are integer seconds with the unit in the
   name; timestamps RFC 3339 UTC.
9. **Long-poll with `waitSeconds` (0 to 20).** Omitted waits the maximum;
   `204` means nothing arrived. Loop on `204`; do not sleep-poll with 0.
10. **Delay at most a week** (`Spooler-Delay-Seconds` 0 to 604800). For
    longer horizons keep the appointment in your database and send when
    due. Cancel a delayed send by discarding its handle; `410` means a
    consumer got there first.
11. **Failed messages need a human or a rule.** List
    `?state=failed&handle=true`, then inspect, recover (back to visible,
    retries reset, optional delay) or discard by handle. A `410` means the
    message moved on since the listing: list again. Failed messages count
    against the spool's caps and block a drain until handled.
12. **Queue changes carry the `uid`** (from the queue JSON) on
    `PATCH` and `DELETE` to hit only the queue you read; `412`
    `queue_replaced` means the name was recreated. Delete requires
    `mode=force` (drop everything now) or `mode=drain` (refuse sends,
    delete once empty). Names are immutable; settings are not.
13. **`507` `spool_full` is backpressure, not billing.** Consume and ack,
    discard failed messages or delete queues, then retry. `429` carries
    `Retry-After` seconds. `503`: retry.
14. **Durability is per response.** On the hosted service `201` on send
    and `204` on ack mean written, synced and confirmed by the spool's
    synchronous copies. The local image promises none of this.
15. **Only use what the docs show.** Do not invent headers, parameters,
    operations or limits. The plan limits and the fixed bounds are below;
    the values in force for an account are at
    https://docs.spooler.sh/limits.

## Queue settings

`PUT` body on create (all optional, omitted = server default); `PATCH` body
on update (omitted = unchanged, at least one field):

| Field | Meaning | Bounds |
| --- | --- | --- |
| `leaseTimeoutSeconds` | unacked delivery is auto-nacked after this; 0 disables | 0 to 31536000, default 300 |
| `maxRetries` | redeliveries before the message is failed; 0 = none | 0 to 65535, default 10 |
| `dedupWindowSeconds` | how long a dedup key is remembered; 0 = dedup off | 0 to 300, default 0 |
| `retentionSeconds` | message lifetime from first visibility; applied value is `effectiveRetentionSeconds` | at least 60, at most the plan's cap |
| `recvRateLimit` | `{intervalMicros, burst}` token bucket shared by all consumers | `intervalMicros` at least 10000; `{0,0}` on update removes it |

Changing `dedupWindowSeconds` forgets every remembered key. Names: 1 to 63
bytes of `A-Za-z0-9_:-`. Dedup keys: 1 to 128 printable ASCII,
case-sensitive.

## Plan limits

Per plan; every limit is enforced by the server, with its own error kind
(`413` `payload_too_large`, `507` `spool_full`, `403` `queue_limit` and
`retention_limit`, `429` `rate_limited`). Stored messages and bytes count
every state on the spool, failed included.

| Plan | Message size | Stored messages | Stored bytes | Queues | Retention cap | Spools | Replicas | Requests |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Solo | 64KiB | 100000 | 2GiB | 1000 | 7d | 1 | 1 | 250/s, burst 250 |
| Team | 64KiB | 250000 | 4GiB | 10000 | 14d | 2 | 2 | 500/s, burst 500 |
| Business | 64KiB | 500000 | 8GiB | 100000 | 30d | 3 | 3 | 1000/s, burst 1000 |

## Errors

JSON `{"kind","message","details"}`; act on status and `kind`, never on
`message`.

| Kind | Status | Do |
| --- | --- | --- |
| `invalid_token`, `dedup_disabled`, `unknown_header` | 400 | fix the request |
| `unauthenticated` | 401 | fix the key |
| `account_suspended` | 402 | settle payment |
| `account_blocked`, `queue_limit`, `retention_limit` | 403 | no retry |
| `queue_not_found`, `spool_not_found` | 404 | verdict, not lag |
| `queue_exists`, `not_failed`, `dedup_claimed` | 409 | verdict |
| `queue_creating`, `queue_busy`, `dedup_in_flight` | 409 | retry shortly |
| `queue_deleting` | 409 | create: retry after deletion; else no |
| `stale_token` | 410 | lease: receive again; handle: list again |
| `queue_replaced` | 412 | re-read the queue for its `uid` |
| `payload_too_large` | 413 | shrink; connection is closed |
| `rate_limited` | 429 | wait `Retry-After` |
| `operation_unconfirmed` | 500 | send: retry only with the same dedup key |
| none | 503 | retry |
| `spool_full` | 507 | make room, retry |

Unknown kinds under a known status read as the status; unknown states are
not yours to act on.

## References

- `references/http-api.md`: every operation with method, path, headers and
  status, curl examples, JSON shapes, the dedup hash recipe.
- Skill `spooler-go`: the Go SDK. Skill `spooler-cli`: the command line.
