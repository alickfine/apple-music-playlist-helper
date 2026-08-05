# Apple Music Playlist Helper Design

## Objective

Build a local macOS command-line helper that adds Apple Music catalog tracks to an existing Music app playlist without model-driven screenshots or per-step UI inspection. The helper must not require Apple Developer Program membership, developer tokens, cloud services, or third-party credentials.

The first supported workflow is adding China-storefront tracks selected by the Apple Music catalog connector to the existing playlist named `试音`.

## Approved Scope

- Accept catalog tracks as structured JSON containing `id`, `name`, `artist`, and an Apple Music URL.
- Add tracks to an arbitrary named user playlist in the macOS Music app.
- Detect duplicates using normalized track name and artist before any UI mutation.
- Fail if the target playlist does not exist unless the caller explicitly supplies `--create`.
- Support `--dry-run` to validate input, permissions, playlist existence, and duplicates without mutation.
- Support `--play-first` to play the first successfully added or already-present requested track.
- Verify every reported addition by reading the target playlist again.
- Continue past per-track failures, report all results, and return a nonzero exit status when any requested track fails.

Out of scope for the first version:

- Deleting, moving, reordering, favoriting, downloading, or sharing tracks.
- Editing existing playlist metadata.
- Apple Music API authentication or Developer Program integration.
- Screenshot recognition, fixed screen coordinates, or model-in-the-loop UI control.
- General Music app automation unrelated to playlist insertion.

## Alternatives Considered

### Native Swift CLI with Accessibility API — selected

Use Swift and `AXUIElement` to identify Music app elements by stable accessibility identifiers and catalog track IDs. This approach is local, testable, does not require screenshots, and can keep business logic independent from the live app driver.

### AppleScript with System Events

This is simpler to prototype but depends more heavily on localized menu strings and UI hierarchy. It remains useful for read-only playlist inventory where the Music scripting dictionary is reliable, but it is not the primary mutation driver.

### macOS Shortcuts

Shortcuts offers a convenient permission model, but its Music actions do not provide a dependable way to select exact Apple Music catalog versions by storefront catalog ID and then verify each insertion. It is not used in version one.

## User Interface

The executable is named `am-playlist`.

Primary command:

```bash
am-playlist add --playlist "试音" --input tracks.json
```

Optional flags:

```text
--create               Create the playlist if it does not exist.
--dry-run              Perform no mutations.
--play-first           Play the first requested track after verification.
--timeout <seconds>    Per-track wait timeout. Default: 8.
--json                 Emit machine-readable JSON results.
```

Input schema:

```json
{
  "playlist": "试音",
  "tracks": [
    {
      "id": "905228611",
      "name": "被遗忘的时光",
      "artist": "蔡琴",
      "url": "https://music.apple.com/cn/album/example/905228605?i=905228611"
    }
  ]
}
```

The `--playlist` option overrides the optional top-level `playlist` field. Each URL must use HTTPS, use the `music.apple.com` host, and contain an `i` query parameter equal to the supplied numeric catalog ID.

## Architecture

The Swift package is divided into focused units:

- `PlaylistCore`: input models, validation, normalization, duplicate detection, result aggregation, and workflow orchestration.
- `MusicAppProtocol`: interfaces for playlist inventory, playlist creation, track insertion, verification, and playback.
- `MusicAccessibilityDriver`: the production implementation using Music app URL navigation and macOS Accessibility APIs.
- `MusicScriptReader`: a narrow read-only adapter for playlist and track inventory through the Music scripting dictionary when available.
- `AMPlaylistCLI`: argument parsing, JSON input/output, exit codes, and user-facing diagnostics.

The workflow depends only on protocols. Unit and driver-contract tests use deterministic fakes and accessibility fixtures; they never launch or mutate Music.

## Data Flow

1. Decode the JSON document and CLI options.
2. Validate every track before launching Music.
3. Check Accessibility authorization without prompting. If missing, return `permission_denied` with the exact System Settings location. A future explicit setup command may request permission, but ordinary `add` never triggers an unexpected prompt.
4. Read the target playlist inventory.
5. If the playlist is missing, fail unless `--create` is present.
6. Normalize Unicode, whitespace, case, and punctuation for the requested and existing `(name, artist)` keys.
7. Mark existing matches as `skipped_duplicate`.
8. For each remaining track, open its exact catalog URL in Music.
9. Poll the Accessibility tree until an album-track element containing the requested catalog ID appears or the timeout expires.
10. From that exact element, invoke its `More` action and select the exact target playlist.
11. Re-read the playlist and verify the normalized `(name, artist)` key is present.
12. Optionally play the first requested track only when `--play-first` was supplied.
13. Emit a complete result summary and derive the process exit status.

## Safety Invariants

- Never click a track by list position, visual coordinate, or approximate title.
- Never select a different catalog ID as a fallback.
- Never create a playlist without `--create`.
- Never delete, move, reorder, download, share, or alter existing items.
- Never store Apple credentials, browser data, tokens, or cookies.
- Never print private Music library contents beyond the requested playlist and requested track results.
- A failed track does not roll back successful additions because Music provides no safe atomic playlist transaction. The result must clearly identify partial success.
- Re-running the same input is idempotent through preflight duplicate detection.

## Result Model and Exit Codes

Each requested track receives exactly one status:

- `added`: insertion was verified.
- `skipped_duplicate`: the target playlist already contains the normalized name and artist.
- `not_found`: the exact catalog ID did not appear before the timeout.
- `permission_denied`: Accessibility permission is unavailable.
- `playlist_missing`: the target playlist does not exist and `--create` was not supplied.
- `verification_failed`: the insertion action completed but the track was not found during verification.
- `failed`: another explicit, captured error occurred.

Exit codes:

- `0`: every track is `added` or `skipped_duplicate`.
- `2`: invalid CLI arguments or invalid input.
- `3`: missing Accessibility authorization.
- `4`: target playlist missing without `--create`.
- `5`: one or more per-track operations failed after preflight.

## Testing Strategy

All production behavior is developed test-first.

### Unit tests

- Reject nonnumeric IDs, non-Apple hosts, non-HTTPS URLs, and mismatched URL IDs.
- Normalize composed and decomposed Unicode, repeated whitespace, letter case, and common punctuation consistently.
- Detect existing `(name, artist)` pairs and preserve distinct versions with different artists.
- Map result sets to the documented exit codes.
- Confirm `--create`, `--dry-run`, and `--play-first` affect only their documented behaviors.

### Driver-contract tests

- Given an Accessibility fixture with several tracks, select only the element whose identifier contains the requested catalog ID.
- Refuse to act when the exact ID is absent.
- Select only the exact target playlist menu item.
- Time out deterministically through an injected clock.
- Verify that no mutation methods run during `--dry-run`.

### Local integration tests

1. Run `--dry-run` against the existing `试音` playlist.
2. Use a dedicated temporary playlist and add one verified China-storefront track.
3. Run the same command again and verify `skipped_duplicate` with no count change.
4. Remove the temporary playlist only after the user authorizes cleanup; otherwise leave it clearly named for manual removal.
5. Run the final nonmutating acceptance check against `试音`, where an existing track must be reported as `skipped_duplicate` and the current count must remain 58.

## Permissions and Installation

The helper requires Accessibility permission for its executable or hosting terminal. It does not request Full Disk Access, Automation access to unrelated apps, network configuration changes, or Apple account credentials.

The first version builds locally with the installed Swift 6.3 toolchain and macOS 26 SDK. Installation is a local symlink or copied executable under a user-controlled bin directory; no privileged installer is required.

## Success Criteria

- A 20-track catalog input can be processed without screenshots or model inspection of the Music UI.
- Existing requested tracks are skipped without duplication.
- Exact catalog IDs gate all UI mutations.
- The helper verifies additions and reports partial failure precisely.
- Missing playlists are not created without `--create`.
- The automated test suite passes, and the final acceptance check leaves the existing `试音` playlist at 58 tracks.
