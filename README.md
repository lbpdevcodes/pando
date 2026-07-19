# Pando

An end-to-end encrypted terminal messenger. One self-hostable relay, a
full-screen TUI client, and no server-side plaintext — the relay routes sealed
envelopes it can never read. Direct messages, group rooms, file and image
attachments (rendered inline via the Kitty graphics protocol), voice notes,
multi-device accounts, self-destructing messages, and TOFU identity
verification. The behavior contract lives in [docs/SPEC.md](docs/SPEC.md).

The client targets [Ghostty](https://ghostty.org) (truecolor + Kitty
graphics); other terminals work with graceful text fallbacks for images.

## Install

Requirements:

- Ruby >= 4.0
- **libsodium** (the `rbnacl` gem binds it): `brew install libsodium` /
  `apt install libsodium-dev`
- Optional, for voice notes: **sox** (preferred) or **ffmpeg** — recording
  uses `rec`/`ffmpeg`, playback uses `ffplay`/`afplay`/`paplay`
- Ghostty, for inline images and QR codes

```sh
git clone <this repo> && cd pando-ruby
bundle install
bundle exec charming db:setup
```

## Run a relay

One process, WebSocket for message traffic, HTTP for the directory and
rendezvous. The queue survives restarts; offline messages hold up to 24h.

```sh
bundle exec pando-relay --host 0.0.0.0 --port 8787 \
  --db ~/.pando/relay/relay.db --token SECRET --sweep-interval 60
```

Every flag has an env twin: `PANDO_RELAY_HOST`, `PANDO_RELAY_PORT`,
`PANDO_RELAY_DB`, `PANDO_RELAY_TOKEN`, `PANDO_RELAY_SWEEP_INTERVAL`.
`--token` gates every request (clients send it as `X-Pando-Relay-Token`);
`--sweep-interval` controls how often expired queued messages are purged.

## Quickstart

```sh
PANDO_RELAY=http://your-relay:8787 bundle exec pando
```

1. **Onboard** — choose a passphrase. It derives (Argon2id) the key that seals
   your identity and everything at rest under `~/.pando` (override with
   `PANDO_ROOT`). Enrolling as a second device of an existing account is on
   the same screen (`ctrl+p` → *Enroll this device*).
2. **Connect** — the first launch seeds relay config from `PANDO_RELAY`;
   after that manage relays in-app (`ctrl+p` → *Add relay* / *Switch relay*).
3. **Share your invite** — `ctrl+p` → *Copy my invite code* (text) or *Show my
   invite QR* (scannable). Your peer uses *Add contact* (paste) or *Load
   invite from file*. Or skip codes entirely: toggle *Toggle discoverability*
   and peers can *Find contact by fingerprint*, which lands in your *Contact
   requests* inbox to accept or decline.
4. **Talk** — `tab` to the composer, `enter` sends. `ctrl+p` for everything
   else: rooms, attachments (*Attach file*), voice notes (`ctrl+r`), message
   timers, contact verification. `?` shows the key cheat-sheet.

`PANDO_DEMO=1` seeds throwaway demo data on first unlock.

## Development

```sh
bundle exec rspec                      # everything: unit, journey, and live specs
bundle exec rspec --tag ~integration   # skip the in-thread relay specs
bundle exec standardrb                 # lint
script/demo-e2e                        # multi-process E2E demo over a real relay
```

Three spec layers: unit specs; **journey specs** driving the whole app through
a scripted in-memory terminal (`spec/journeys_spec.rb`); and **live specs**
(`spec/integration/`) that boot a real relay and full clients in-process to
prove wire behavior — delivery, rooms, attachments, enrollment, TTL.
