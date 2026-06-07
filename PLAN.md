# Make proofs full-screen, play-then-exit, with a tap-to-reply state

## What changes

Right now a private photo/video "proof" shows up as a thumbnail right inside the conversation. We're going to make proofs their own full-screen moment — the chat just shows that a proof was sent, and watching it happens in a dedicated viewer.

## Features

- **Proofs leave the chat flow.** In a conversation you'll see your written messages as normal chat bubbles. A proof no longer shows its photo/video inline — instead it appears as a small, quiet pill ("📷 a proof"), so you only ever *see* the chats.
- **Side-aligned proof pills.** Their proofs sit on the left, yours on the right, keeping the natural back-and-forth rhythm of the conversation.
- **Tap a received proof to watch it full-screen.** It plays on its own — a photo lingers for a few seconds, a video plays for its length — with a slim progress bar across the top.
- **Watch several in a row.** If a person has sent you more than one proof you haven't seen yet, they play one after another like a story, then the viewer closes itself. You can also swipe down to leave early.
- **No surprise camera.** When a proof finishes, the viewer simply exits back to the conversation. The camera does *not* pop open on its own.
- **The pill flips to "Reply with a proof."** Once you've watched a received proof, its pill in the chat quietly turns into a "Reply with a proof" button. Tapping it opens the camera aimed just at that person — replying is always your choice.
- **Your own proofs stay re-watchable.** A proof you sent shows a calm "You sent a proof" pill you can tap to view again.
- **Press-and-hold to send fast.** On the Proofs list, holding down any person's card jumps you straight into the camera to send that one person a proof.

## Design & feel

- Warm, calm, witness-model — no read-receipt pressure, no nagging badges, just a gentle count.
- The proof pill is understated (a small camera/seal glyph + short label) and fades smoothly into the "Reply with a proof" button after viewing.
- The full-screen player matches the existing story viewer: black canvas, thin top progress bar, the sender's name and "how long ago" up top, the proof's caption resting near the bottom, swipe-down to dismiss.
- Press-and-hold gives a light haptic and a subtle card-press so it feels intentional.
- All motion is soft and eased, and respects reduced-motion settings.

## Screens

- **Proofs list** — the people you trade with; tap to open a conversation, press-and-hold to send a proof instantly.
- **Conversation** — text messages as chat bubbles plus quiet, side-aligned proof pills (tap to watch / reply), unchanged message composer at the bottom.
- **Full-screen proof player** — plays the proof(s), then exits on its own.

## Notes

- The friend profile's "Privately" row keeps linking into this same conversation, so everything stays consistent.
- Existing demo data already includes an unwatched proof or two, so the "tap to view → reply" flow is visible right away.

