# Privacy

Poseboard processes camera frames locally using Apple Vision. Images stay in
memory and are not recorded, logged, or uploaded. The sandbox allows only camera
access. There is no analytics, network client, microphone, screen capture,
Accessibility, Input Monitoring, Apple Events, or keyboard injection.

Teaching saves the name, verbatim prompt text, selected symbol, role, random ID,
recognition tolerance, and normalized hand landmarks. This is personal data even
without photos. It stays in Poseboard/Vocabulary.json within the sandbox's local
Application Support directory. It is not bundled with the app or included in Git.
Deleting an entry removes it from the current vocabulary; system backups may
retain older copies.

Schema version 1 remains readable. Merely opening it does not rewrite it. The
first successful newer-format save preserves Vocabulary-v1-backup.json in the
same private directory. Unknown or corrupt vocabularies are preserved and disable
all vocabulary writes.

Prompt drafts and user-supplied context cards exist only in memory. Only cards
explicitly included in the prompt contribute text to review and delivery. Excluded
cards remain in memory until removed, cleared, or the app quits. Card titles and
included text are visible in the review. Nothing is automatically collected from
other apps or the clipboard. Phrases are joined verbatim. Depth adds a visible fixed
instruction. There is no generative model rewriting text or inferring meaning from
private app content. Starter phrases are not saved until you explicitly teach or
save them.

Copying requires review and confirmation and replaces the system clipboard.
Poseboard does not read or archive existing clipboard contents. The clipboard
receives a transient-content hint, which other software may choose to honor.
System clipboard syncing or other applications' clipboard storage are outside
Poseboard's control.

Native text Services return only the exact confirmed prompt using the private
pasteboard supplied by macOS for that explicit request. Poseboard does not inspect
the destination UI or simulate a paste or Send key. A confirmation expires after
90 seconds, is tied to one draft and request, and cannot be replayed. Destination
apps control insertion and subsequent transmission.

Camera startup is always explicit. It stops on backgrounding unless Float has
been explicitly enabled for this session. The floating window must stay visible.
Hiding/closing the window, sleep, and session deactivation stop capture and cancel
pending insertion. Camera device identifiers are used in memory only.

Signing identities, certificates, account credentials, camera captures, saved
vocabularies, and machine-specific paths are excluded from source publication.
An Apple-signed binary can disclose the certificate's developer name. Review
attachments before sharing a bug report; do not attach private prompts, a
vocabulary, camera images, or personal filesystem paths.
