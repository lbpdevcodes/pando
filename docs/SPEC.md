# Pando — Functional Specification

Pando is private, end-to-end encrypted terminal chat: messages are readable only by the
people in the conversation, delivered through self-hosted relays that never see plaintext
and never retain delivered messages. This document is the product spec the implementation
is tested against. It describes behavior, not implementation; where the original Go app's
behavior was an implementation accident rather than a product decision, this spec records
the intended behavior instead.

## Product invariants

1. **The relay is crypto-blind.** It sees mailbox addresses, ciphertext sizes, and
   timestamps — never message content, contact names, or room structure. All control
   traffic (typing, receipts, contact exchanges, room management) is encrypted the same
   as chat text.
2. **Live messages are never stored.** A message to an online recipient is forwarded and
   forgotten. Only messages to offline recipients are queued — for at most 24 hours or
   until first login, whichever comes first.
3. **Local data is encrypted at rest.** Everything sensitive on disk (identity, contacts,
   history, attachments) is unreadable without the profile passphrase.
4. **Trust is explicit.** Every contact shows a trust level; users can verify each other
   out-of-band by comparing short fingerprints. A contact whose keys change is flagged
   loudly, never silently accepted.

## Identity

- A user has an **account** with a short **fingerprint** (16 hex chars) used for
  out-of-band verification and directory lookup.
- An account owns one or more **devices**; each device has its own keys and its own
  **mailbox** (its address on a relay). Messages fan out to every device of every
  participant, so all of a contact's devices see the conversation.
- **Enrollment** adds a device to an existing account: the new device displays an offer
  (code or QR); an already-enrolled device approves it; the account identity transfers
  encrypted to the new device, which then works like any other.
- A profile is protected by a **passphrase** chosen at creation, required at every
  launch, and changeable later. A wrong passphrase refuses to open the profile with a
  clear error. Non-interactive unlock is possible via environment variable (for scripts).

## Contacts

Ways to connect two accounts:

- **Invite code**: either party generates a compact shareable code (text or QR) carrying
  their public identity; the other party pastes/scans it. Codes contain no secrets —
  security comes from checking fingerprints out-of-band.
- **Rendezvous**: both parties enter the same short human-friendly code; the relay
  brokers an encrypted exchange of identities without either party seeing the other's
  code contents in advance. Slots are single-use and short-lived.
- **Directory**: an account may opt in to publishing its identity to a relay's directory,
  discoverable by fingerprint. Publishing is required to receive messages on that relay;
  discoverability (being findable by others) is a separate opt-in.
- **Contact request**: knowing someone's identity is not enough to message them; the
  first contact is a request the recipient sees in an inbox and explicitly accepts or
  declines. Accepting creates the contact both ways.

Trust levels per contact: `unverified` (exchanged via invite/directory), `verified`
(fingerprints compared manually), `key changed` (the pinned key no longer matches —
shown as a prominent warning until re-verified).

## Conversations

Direct messages and group **rooms** are the same thing to the user: a conversation with
one or more participants. Behaviors common to both:

- **Transcript** with newest messages at the bottom; the view follows new messages when
  at the bottom and holds position when scrolled up.
- **Delivery status** per outgoing message: `pending` (not yet accepted by relay) →
  `sent` (relay accepted; queued or forwarded) → `delivered` (a recipient device
  decrypted it) or `failed` (relay rejected / timed out; failure is visible and the
  message can be retried).
- **Typing indicators**, best-effort and ephemeral (never queued for offline peers).
- **Message TTL / self-destruct**: a per-conversation setting; expired messages disappear
  from both ends' history and are purged in the background.
- **Offline delivery**: messages to offline devices wait in the relay queue (≤24h);
  recipients receive them on next connect, in order, exactly once.
- **History** is local, per-device, encrypted, and survives restarts. A device only has
  history from when it was enrolled; rooms can backfill recent history to new members
  from an existing member.

Rooms additionally: any member can invite contacts into the room; membership changes are
visible to all members; each member sees a consistent member list.

## Attachments

- **Files and images** send inside the same encrypted channel, size-limited (relay caps
  frames; large files chunk transparently). Recipients see filename, type, and size, and
  attachments save decrypted only on explicit action.
- **Images** display inline in the transcript (terminal graphics), downscaled to fit.
- **Voice notes**: record from the composer (start/stop), sends as an audio attachment;
  recipients play back in-app via an installed system player. Recording shows elapsed
  time and can be cancelled.

## The client

A full-screen TUI (this port targets **Ghostty** exclusively; truecolor and Kitty
graphics are assumed) with:

- **Layout**: conversation sidebar (unread counts, typing hints, trust badges) +
  transcript + multi-line composer. Narrow terminals collapse to a single pane.
- **Command palette** (`ctrl+p`): the hub for every action — add contact, verify,
  requests inbox, rooms, relays, theme, TTL, help.
- **Keys** (defaults): `tab` switch pane; `↑/↓` navigate sidebar or scroll; `pgup/pgdn`,
  `home/end` in transcript; `enter` send; `shift+enter` newline; `esc` cancel/back;
  `?` help when composer is empty; `ctrl+c`/`q` quit (per Charming convention).
- **Status**: connection state (connected / reconnecting / offline) always visible;
  reconnection is automatic with backoff; sending while offline queues locally as
  `pending` and sends on reconnect.
- **Relays**: a user can configure multiple relays with optional access tokens and
  switch the active one. Relay problems surface as human-readable status, not stack
  traces.
- **Themes**: selectable at runtime, persisted.

## The relay server

A single self-hostable process:

- WebSocket endpoint for message traffic; HTTP endpoints for directory, rendezvous, and
  health checks.
- **Mailbox ownership is proven, not asserted**: connecting clients answer a fresh
  challenge; only the holder of a mailbox's published keys can subscribe to it.
- Optional relay-wide access token gating all use.
- Per-mailbox queue caps (message count and total bytes) and a per-frame size cap;
  exceeding them fails the send with a distinct error the sender can show.
- Queue survives relay restarts; expired and delivered messages are purged.
- Deployable via a single binary/gem + a data directory; configured by flags/env.

## Explicit non-goals (v1)

- Forward secrecy / key ratcheting (static device keys, as the original).
- Multi-relay redundancy for a single conversation (one active relay at a time).
- Server-side anything-plaintext: no web client, no push notifications.
