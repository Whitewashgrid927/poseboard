# Poseboard

A local macOS app for a personal vocabulary of held two-hand poses. Apple Vision tracks the hands; a small geometric recognizer compares both hands and their relative spacing with the examples you teach. This is a separate app from Gestures.

Requires an Apple-silicon Mac with macOS 26 or newer and a camera. The interface uses native SwiftUI Liquid Glass, including an expandable floating vocabulary panel.

## Try it

1. Open Poseboard and click **Start camera**. Allow macOS Camera access when prompted.
2. Click **Teach a pose**, enter a short meaning, and choose a symbol. You can also select a starter meaning and choose **Teach this pose**.
3. Click **Capture example 1**. After the countdown, hold both hands in a comfortable pose for about one second. Keep your wrists and fingers in view and your hands separated.
4. Relax, then capture examples 2 and 3 of the same pose. Click **Save pose**.
5. Make the pose again in the main camera view. A steady match proposes your message. Click **Show** to display it in large type. Nothing is sent or spoken automatically.

Drag the small handle at the top of the floating panel to resize it, or click the chevron to expand or collapse. Vocabulary entries also work as clickable messages without the camera. Selecting an entry opens its saved landmark drawing, **Use message**, **Teach again**, and **Delete**.

Starter meanings have no predefined gestures. They remain **Not taught yet** until you assign your own poses. Saved drawings show each hand shape independently; use the same relative spacing you demonstrated during teaching.

## Privacy and boundaries

- Camera images are processed in memory and never saved or uploaded.
- The app is sandboxed with camera access only. It has no network, microphone, screen capture, Accessibility, or automation entitlements and no analytics or external dependencies.
- Your message text, selected symbols, and normalized hand-landmark examples are stored in the app's private local Application Support folder. No camera IDs, photographs, faces, audio, or video are stored in the vocabulary.
- Camera capture begins only after you click Start. It pauses when the app goes into the background, its window is hidden or closed, or the Mac sleeps or its session becomes inactive. Closing the last window quits the app.
- Recognition requires exactly two observations, enough confident landmarks on each hand, a stable match, and a clear margin over other meanings. Uncertain, stale, overlapping, or extra-hand observations do not create a new recognized message.
- A previously recognized message can stay visible as a labeled draft while you reach for the Show button. You review and confirm it. It is not automatically delivered.
- This version learns stationary poses, not movement sequences or an existing sign language. Recognition is personal and camera-dependent. Hands covering one another or tightly hidden fingertips can prevent detection. Keep the same general orientation, spacing, and hand shapes as your examples.
- If a saved vocabulary cannot be read, the file is preserved and all vocabulary writes are disabled. There is no silent replacement with defaults.

## Build and checks

Select a full Xcode installation that includes the macOS 26 SDK or newer, then run:

```sh
bash Scripts/test.sh
bash Scripts/build.sh /path/to/output
python3 Tests/PrivacyTests.py
python3 Scripts/privacy-check.py --history
```

`SIGNING_IDENTITY` may be supplied for local signing; without it the build uses an ad-hoc signature. No certificate, signing identity, developer account, or machine path is embedded in the source. This development build has not been notarized for distribution to other Macs.

The focused tests cover two-hand geometry, translation/scale invariance, distinct poses, ambiguity and collision rejection, missing/extra hands, stale frames, temporal holds, malformed storage, save/reload, and explicit message confirmation. Live camera accuracy must be checked using your own taught poses.

## Development

Changes are reviewed through pull requests targeting `main`. See [Contributing](CONTRIBUTING.md) for the checks, commit-email privacy, and camera/recognition boundaries to preserve. The [privacy notes](PRIVACY.md) describe local data and publication limits.

Only source and synthetic tests belong in Git. Personal vocabularies, camera captures, compiled apps, signing material, and local review records are excluded. GitHub Actions runs privacy checks, tests, and an ad-hoc build without publishing binaries or using developer credentials.

Apple documentation: [Liquid Glass](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views), [Vision hand poses](https://developer.apple.com/documentation/vision/vndetecthumanhandposerequest).
