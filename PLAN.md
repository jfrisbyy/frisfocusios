# Add a Save-to-camera-roll button in the photo/video editor

## What you'll get

A **Save** button in the photo/video editor that drops the moment straight into your phone's camera roll — exactly as you've edited it.

### Features
- A **download arrow button** appears in the top bar of the editor, right next to the close (X) — just like Instagram and Snapchat.
- Tapping it saves the **edited version** to your camera roll: the chosen filter, any text captions, task stickers, and freehand drawings are all baked in, matching exactly what you see on screen.
- Works for both **photos and videos**.
- Saving is independent of sharing — you can save and still post, save and send privately, or just save and back out.
- The first time you save, your phone asks permission to add to your photos. If that permission is off, a calm prompt offers to open Settings.

### Design & feel
- A small circular button with a download-arrow symbol, styled to match the existing top-bar buttons (retake / close) — same dark translucent circle, same size.
- While it's working, the button shows a brief spinner (videos take a beat longer because the edits are rendered into the clip).
- On success, a soft confirmation appears in the center ("Saved to your camera roll"), reusing the same gentle toast already used when sending a proof. A light haptic taps on success.
- If something goes wrong or permission is denied, a quiet, friendly message explains why — never an alarming error.

### Where it appears
- Only on the **capture editor** — the screen you land on right after taking a photo or recording a video. The top bar keeps the retake arrow on the left and any earned-task badge centered; the new Save button sits just left of the close (X) on the right.

### Behind the scenes (no visible change)
- Adds the system permission needed to add items to your photo library, with a friendly description ("Save a photo or video from your day to your camera roll").
