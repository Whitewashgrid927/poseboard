# Poseboard

A local macOS app for a personal vocabulary of two-hand signs. Teach a sign, assign
a sentence or several paragraphs, and combine signs into a prompt for your AI
conversation. Apple Vision tracks the hands; a geometric recognizer compares
their landmarks with the examples you teach. Prompt assembly joins your exact
text locally. No language model, account, API key, or network connection is needed.

Requires an Apple-silicon Mac, macOS 26 or newer, and a camera for teaching signs.
The interface uses native SwiftUI Liquid Glass with an expandable vocabulary panel.

## Download

[Download Poseboard 0.2.0 for Apple silicon](https://github.com/Whitewashgrid927/poseboard/releases/download/v0.2.0/Poseboard-0.2.0-macOS-arm64.zip).
No Xcode or source build is needed.

1. Unzip the download and drag **Poseboard.app** into **Applications**.
2. Open Poseboard. Camera capture starts off.
3. Choose **Teach a sign**, enter the text it should add, and start the camera
   when you are ready to capture your three examples.

The app is signed with Apple Developer ID and notarized by Apple. The
[0.2.0 release page](https://github.com/Whitewashgrid927/poseboard/releases/tag/v0.2.0)
includes installation instructions, checksums, and the matching source archive.
Your saved vocabulary is stored separately and is not included in a download.

## Teach and compose

1. Choose **Teach a sign**. Give it a short name and write the full text it should
   add. Use **Instruction** for a main request or **Modifier** for an additional
   requirement. Both keep the exact words you write.
2. Click **Start camera**, allow the normal macOS Camera prompt, and capture three
   examples of a comfortable two-hand pose. Keep wrists and fingers visible and
   both hands separated. Relax between examples, then save.
3. Hold a taught sign steadily. Its text joins the prompt once. Lower **both**
   hands for about half a second before adding the next sign. Ambiguous, stale,
   or low-confidence observations cannot append text.
4. Choose an optional depth instruction, add context you explicitly paste, or
   edit the assembled draft. Manual edits pause gesture additions until you
   choose **Use signs**. **Undo** removes the last sign; **Clear** also removes context.
5. Review the exact text before copying or inserting it. Poseboard never presses Send.

You can save a phrase without a sign and add it by clicking its vocabulary tile.
**Edit text** preserves a sign's saved examples; **Teach again** replaces them only
after three new valid examples pass the conflict checks. New vocabularies are empty.

The vocabulary handle expands, collapses, and resizes the panel. **Float** keeps
the window above other apps and, if the camera is already on, allows tracking
while that window remains visible. Float starts off on every launch. Hiding or
closing the window, sleep, and session deactivation always stop camera capture.

## Confirmed insertion

Poseboard provides a native macOS text Service, retaining its camera-only sandbox:

1. Place the cursor in the destination app's editable chat draft.
2. Choose **Services → Insert Poseboard Prompt** from that app's menu.
3. Poseboard displays your draft for review. Choose **Confirm & insert** to return
   that exact text to the requesting field. Nothing is sent automatically.

Keep the destination field unchanged while the request is pending. Confirmation
is bound to that request, expires after 90 seconds, and can be used only once.
Canceling or switching away returns no text. The destination app controls whether
returned text is inserted and may replace its selected text; Poseboard cannot
independently verify insertion without broader system access.

Text Services support depends on the destination app and editable field.
A universal cross-app insertion claim is not made. If the service is unavailable,
use **Review & copy**, then paste manually. Copy replaces the system clipboard
only after confirmation. Poseboard keeps no clipboard history. The system or
other clipboard tools can have their own storage or syncing behavior.

A shortcut can be assigned under System Settings → Keyboard → Keyboard Shortcuts
→ Services. No Accessibility, Input Monitoring, Apple Events, or screen-capture
permission is needed.

## Privacy and safety

- Camera frames stay in memory; they are never recorded, logged, or uploaded.
- The sandbox permits only camera access. There is no network client, analytics,
  microphone access, external dependency, keyboard injection, or reading of other apps.
- Saved vocabulary contains your labels, prompt text, symbols, roles, recognition
  tolerances, and three normalized pairs of landmarks for each taught sign.
- Drafts and explicitly supplied context stay in memory, disappearing on quit.
  Only confirmed Copy or Service delivery transfers the prompt out of Poseboard.
  Sending it onward is controlled by your destination AI app.
- Recognition requires exactly two observations, confident landmarks, a stable
  hold, and a clear margin over other meanings. Lowering both hands rearms it;
  missing frames, low-confidence observations, or additional hands do not count
  as that release. The camera must report no detected hands for a continuous interval.
- Older vocabularies load without being rewritten. The first successful edit saves
  schema version 2 and preserves a private version 1 backup. Corrupt or unsupported
  files remain untouched and disable vocabulary writes.
- This app learns stationary personal poses. It does not translate an existing
  sign language or recognize arbitrary motion sequences. Depth is controlled by
  the visible selector or your own taught modifier phrases.

## Build and checks

Select a full Xcode installation containing the macOS 26 SDK or newer, then run:

    bash Scripts/test.sh
    bash Scripts/build.sh /path/to/output
    python3 Tests/PrivacyTests.py
    python3 Scripts/privacy-check.py --history

The build script uses ad-hoc signing unless SIGNING_IDENTITY is supplied in the
environment. No signing credentials or machine paths belong in the source.
Public releases require a separate Developer ID signing and notarization process.

Tests use synthetic landmarks and temporary stores. They cover recognition,
ambiguity, stale frames, release rearming, composition bounds, verbatim paragraphs,
old-vocabulary migration, corruption preservation, and confirmation identity,
destination, expiration, cancellation, and replay prevention. Automated checks
do not establish live recognition accuracy for every user or destination-app compatibility.

## Development

Changes are reviewed through pull requests targeting main. See
[Contributing](CONTRIBUTING.md) for checks and commit-email privacy, and
[Privacy](PRIVACY.md) for storage boundaries. Only source and synthetic tests belong
in Git; personal vocabularies, captures, compiled apps, signing material, and local
verification records remain excluded.

Apple documentation: [Liquid Glass](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views),
[Vision hand poses](https://developer.apple.com/documentation/vision/vndetecthumanhandposerequest),
[text Services](https://developer.apple.com/documentation/bundleresources/information-property-list/nsservices).
