# Privacy

Poseboard processes camera frames on the Mac using Apple's Vision framework.
Frames remain in memory and are not recorded, logged, or uploaded. The app has
no analytics, network client, microphone, screen recording, Accessibility, or
automation permission. Its sandbox entitlements allow only the app sandbox and
camera access.

Teaching saves the meaning text, chosen symbol, random entry ID, recognition
tolerance, and three normalized pairs of hand landmarks. This personal vocabulary
is stored in `Poseboard/Vocabulary.json` inside the app's local Application Support
directory, within its sandbox container. It is not bundled with the app or part
of this repository. It should be treated as personal data even without photos.
Deleting an entry removes it from the current vocabulary; system backups may
retain earlier copies according to the user's backup settings.

Camera identifiers are used in memory to select a device. They are not stored in
the vocabulary or sent anywhere. The repository includes source, original icon
drawing code, and synthetic tests only. It contains no trained personal vocabulary,
camera captures, signing certificates, account credentials, or machine-specific
configuration.

Local builds use ad-hoc signing unless a developer supplies their own signing
identity through the environment. Do not commit that identity or its credentials.
A separately distributed Apple-signed binary can disclose the certificate's
developer name; source publication does not require distributing that binary.

When reporting a problem, describe the behavior without attaching your vocabulary,
camera image, personal filesystem path, or full diagnostic archive. Review any
attachment before sharing it.
