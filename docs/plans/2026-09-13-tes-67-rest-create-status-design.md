# TES-67 REST Create and Status Design

## Scope

Expose authenticated server creation and status lookup through the existing
`cloud-control` HTTP process. Reuse `ControlStore.mutate` and
`ControlStore.getServer`; do not add another lifecycle path, dependency, or
database model.

## HTTP contract

`POST /v1/servers` accepts JSON with `client_request_id`, `name`, and
`eula_accepted`. A missing or false EULA value returns `409` with
`action_required: "accept_eula"`. A valid request returns the existing durable
accepted-mutation response with status `202` without waiting for runtime work.
The creation event records the explicit EULA acceptance.

`GET /v1/servers/:server_id` returns the authenticated owner's logical server,
its typed state, the current cold allocation path, and the status URL. It
includes the game endpoint only while the server is `running`; callers cannot
observe another owner's server.

Both routes require the existing bearer machine identity. Invalid JSON,
unsupported content, malformed IDs, and oversized bodies return typed client
errors. Existing `ControlError` status codes remain the source of truth for
ownership, validation, and idempotency failures.

## Implementation

Extend the existing request handler with a small bounded JSON reader and route
matching. Depend on a structural subset of `ControlStore` so the Node test can
use a minimal fake service. Extend the create mutation with the accepted EULA
flag so it participates in the idempotency digest and event evidence.

The allocation path is `cold` for TES-67 because warm allocation does not exist
yet. TES-153 will persist and return `warm` when that path is implemented.

## Verification

Add focused Node HTTP tests for authentication, EULA action-required behavior,
asynchronous creation, stable status reads, endpoint gating, ownership errors,
invalid input, and request-size limits. Extend the existing PostgreSQL lifecycle
test to verify that EULA acceptance is part of the durable idempotency record and
creation event. Run `npm run check`; run the integration test when a disposable
PostgreSQL URL is available.
