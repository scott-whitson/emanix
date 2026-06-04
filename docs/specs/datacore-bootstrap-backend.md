# Datacore Bootstrap Backend Design

This is design-only companion to `docs/specs/datacore-bootstrap.openapi.yaml`.
It describes how datacore should implement the bootstrap enrollment flow that
`ventoy/bootstrap.sh` already speaks.

## Goal

Turn datacore into enrollment portal for blank machines:

1. User opens datacore.
2. User signs in with normal datacore auth.
3. User approves new device name + role.
4. Datacore mints short-lived bootstrap token.
5. Client joins Headscale, fetches dotfiles, runs repo bootstrap.
6. Client reports success.

No long Headscale auth key on USB.

## Non-goals

- No sync engine here.
- No device policy UI beyond bootstrap approval.
- No secret storage on client.
- No attempt to replace repo bootstrap with backend logic.

## State machine

Suggested bootstrap session states:

- `pending` — session created, waiting for browser approval.
- `waiting` — same meaning as pending; useful if UI wants a distinct label.
- `approved` — user approved, bootstrap token issued.
- `denied` — user rejected device.
- `expired` — session TTL elapsed.
- `rejected` — backend rejected request for policy reasons.

Poll contract should map expired sessions to `410 Gone` so the client can stop cleanly.

Suggested completion state:

- `acknowledged` — client finished bootstrap and datacore recorded it.

## Core data model

### `bootstrap_sessions`

Store one row per enrollment attempt.

Suggested fields:
- `id` — session ID, unguessable.
- `device_name` — requested friendly name.
- `hostname` — requested hostname.
- `role` — requested profile.
- `state` — session state.
- `device_code` — short human-readable code.
- `verification_url` — browser URL.
- `approved_by_user_id` — authenticated user who approved.
- `bootstrap_token_hash` — hashed token, never store token plaintext.
- `bootstrap_token_expires_at` — TTL for token.
- `headscale_login_server` — returned login server URL.
- `dotfiles_archive_url` — preferred bundle URL.
- `dotfiles_git_url` — fallback git URL.
- `ssh_trust_bundle` — SSH trust material returned after approval.
- `device_id` — datacore device record if created.
- `created_at`, `updated_at`, `expires_at`, `completed_at`.

### `devices`

Optional but likely useful.

Suggested fields:
- `id` — device ID.
- `user_id` — owner.
- `name` — canonical name.
- `hostname` — active hostname.
- `role` — role/profile.
- `status` — pending / active / disabled / retired.
- `last_bootstrap_session_id`.
- `last_seen_at`.

## Endpoint behavior

### `POST /api/bootstrap/sessions`

Create session.

Responsibilities:
- validate `device_name`, `hostname`, `role`
- accept optional `machine_ssh_public_key` for reciprocal SSH trust
- create session row
- mint `session_id`
- mint `verification_url`
- mint `device_code`
- set expiry
- return polling interval

Suggested response fields:
- `session_id`
- `device_code`
- `verification_url`
- `expires_at`
- `poll_interval_seconds`

Notes:
- `device_name` and `hostname` may be same, but backend should allow them to differ.
- If datacore wants to force hostname policy, normalize here.

### `GET /api/bootstrap/sessions/{session_id}`

Poll session state.

Responsibilities:
- verify session exists and not expired
- return `pending`/`approved`/`denied`/`expired`
- if approved, include bootstrap token and source data

Suggested approved payload:
- `bootstrap_token`
- `headscale_login_server`
- `dotfiles_archive_url`
- `dotfiles_git_url`
- `ssh_trust_bundle`
- `device_id`
- `hostname`
- `expires_at`

Rules:
- bootstrap token should be one-time and short-lived
- if token already consumed, backend should either keep returning approved with same token until expiry, or return approved plus explicit consumed flag; pick one and keep it stable
- client currently tolerates missing dotfiles URLs and falls back to USB mirror, so backend may omit them if needed

### `POST /api/bootstrap/sessions/{session_id}/approve`

Browser/UI approval action.

Responsibilities:
- require normal datacore user auth
- confirm device name and role
- record approver
- optionally create or assign device record
- mint bootstrap token and any source URLs
- transition session to approved

Implementation note:
- frontend can call this endpoint, but the browser page may also submit a form and redirect. Keep API stable either way.

### `POST /api/bootstrap/sessions/{session_id}/complete`

Client completion callback.

Responsibilities:
- record bootstrap success/failure
- mark session completed
- update device last-seen / hostname / role / status
- stay idempotent

Suggested request fields:
- `status`: `ok` or `error`
- `bootstrap_token` required
- `device_name`
- `role`
- `hostname`
- `device_id` optional
- `message` optional
- `exit_code` optional

If `status=ok`, mark device active.
If `status=error`, keep session history and expose failure reason in UI.

### `GET /bootstrap/{session_id}`

Human verification page.

Responsibilities:
- show code and device name
- prompt login if not already authenticated
- approve or deny device
- call approval endpoint or equivalent server action

## Bootstrap token rules

This is the critical security boundary.

Requirements:
- short TTL, 10–30 minutes is enough
- one-time use
- scoped to one session and one device
- never shown in logs
- store only hashed form in database
- rotate or invalidate on completion/expiry

Suggested properties:
- token bound to `session_id`
- token bound to `hostname`
- token bound to `headscale_login_server`
- optional binding to user ID
- approved poll response should keep returning the same token until expiry; backend separately tracks whether Headscale already consumed it

## Auth model

- `POST /api/bootstrap/sessions` and `GET /api/bootstrap/sessions/{session_id}` stay client-open.
- `POST /api/bootstrap/sessions/{session_id}/approve` and `GET /bootstrap/{session_id}` require normal datacore user auth.
- Completion callback stays session-scoped and unauthenticated beyond the session token response flow.
- `machine_ssh_public_key` may be accepted at session create or approval time, but should be present before approved trust bundle is emitted.

## Headscale integration

Datacore should return `headscale_login_server` from the approved session.

Backend choices:
1. Datacore stores fixed Headscale login server in config.
2. Datacore computes it per environment or host class.
3. Datacore returns nil only if bootstrap flow is in rescue mode.

Preferred: always return it for normal enrollment.

## Dotfiles source selection

Backend may return one or both of:
- `dotfiles_archive_url` — preferred
- `dotfiles_git_url` — fallback

Suggested order:
1. archive URL
2. git URL
3. client USB mirror fallback

This keeps bootstrap resilient when datacore storage or git backend is degraded.

## Cleanup jobs

Suggested periodic tasks:
- expire pending sessions past TTL
- revoke unused bootstrap tokens
- prune stale approval pages
- archive completed sessions
- mark orphaned device records inactive if bootstrap never completed

## SSH trust material

Phase 1 bootstrap should also establish reciprocal passwordless SSH between datacore and the target machine.

Explicit API shape:
- client provides `machine_ssh_public_key` during enrollment
- approved response returns `ssh_trust_bundle`
- backend stores the machine key and adds it to the datacore-side authorized_keys or equivalent trust store
- client installs datacore trust bundle before handing off to repo bootstrap

Suggested `ssh_trust_bundle` content:
- `ssh_user` — user on datacore for outbound SSH from machine
- `known_hosts` — known_hosts text block or host key lines for datacore
- `ssh_config_snippet` — optional SSH config snippet for datacore access
- `host_ca_public_key` — optional CA key if datacore later moves to SSH certs

This can start with plain key-based trust and later move to SSH CA / certs.

## Phase 2 sync hooks

Do not build full sync into bootstrap path, but leave room for it.

Likely future endpoints:
- `POST /api/devices/{device_id}/heartbeat`
- `POST /api/devices/{device_id}/sync/request`
- `GET /api/devices/{device_id}/sync/bundle`
- `POST /api/devices/{device_id}/rotate-token`

Phase 2 can reuse the same device registry created during bootstrap.

## Suggested implementation order

1. Add session table.
2. Implement `POST /api/bootstrap/sessions`.
3. Implement polling `GET /api/bootstrap/sessions/{session_id}`.
4. Implement browser approval endpoint/page.
5. Mint short-lived bootstrap token.
6. Implement completion callback.
7. Add cleanup job.
8. Add phase 2 sync endpoints later.

## Failure handling

- Session expired: return `expired` and 410.
- Session missing: return 404.
- Approval denied: return `denied` and a message.
- Token invalid or reused: reject at Headscale join time.
- Completion failure: keep session approved, mark completion retryable.

## Practical backend invariant

If `ventoy/bootstrap.sh` can do its job with only the approved session response, backend is good enough.

That means datacore must reliably provide:
- `bootstrap_token`
- `headscale_login_server`
- at least one dotfiles source or an intentional omission for USB fallback
- `hostname` when backend wants to override client default
