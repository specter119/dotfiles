# OneNote extension

Development notes for the `onenote` Pi extension: what it may and may not do, and the OneNote
behaviour it depends on.

This belongs here rather than in the repository-level `AGENTS.md`, which covers the dotfiles
repository itself. The extension is expected to move to its own project, so its contract travels
with its code.

Drives the **Microsoft OneNote desktop application on the Windows host** from Pi running inside
WSL, over the OneNote COM automation interface.

Graph was rejected on purpose: it needs an app registration and a write scope (the available one
has none), and it cannot see the user's already-signed-in local notebooks. COM needs no API scope,
no admin consent and no network, and it writes through the same client the user is already using,
so the change syncs like any other edit.

It is also **silent**: the COM proxy starts OneNote without a visible window and never takes focus,
so it does not disturb whatever the user is doing on the Windows desktop.

## Invariants

The rest of this file explains *why*, but these are the rules to keep:

1. Never send an `objectID` on new content; let OneNote assign it.
2. Never hand-build outline XML. Edit a whole outline through `onenote_edit`, which echoes back
   OneNote's own XML for everything it is not changing.
3. Never put a `lastModified` comparison back into a write path.
4. Keep the transport exactly as it is: no `-File`, no environment variables for paths, no
   namespace manager, no `[string]` on parameters that receive `$null`.

## Files

| File | Role |
| --- | --- |
| `index.ts` | Registers the `onenote_*` tools, owns dry-run/confirm, reads image files, base64-encodes payloads |
| `bridge.ps1` | The whole COM layer. Run as a one-shot `powershell.exe` process per call |

**Why one process per call instead of a resident worker:** a warm
`New-Object -ComObject OneNote.Application` costs **6-11 ms** (cold: 226 ms), so PowerShell process
startup dominates and a resident worker with its own lifecycle buys almost nothing. Measured, not
assumed.

## Tool surface

Exposed to **codemode** rather than declared directly, so sessions that are not doing OneNote work
carry no extra tool list. Each tool returns text for the transcript and `structuredContent` for
scripts.

| Tool | Kind |
| --- | --- |
| `onenote_notebooks`, `onenote_pages`, `onenote_search`, `onenote_read_page` | read-only |
| `onenote_create_page`, `onenote_append_lines`, `onenote_insert_table`, `onenote_insert_image` | additive |
| `onenote_edit` | rewrites paragraphs in place — destructive |
| `onenote_delete_page` | destructive, goes to the recycle bin |

Reads are free. Every write is **dry-run by default**, and the dry run is a real bridge call that
reports the exact change set OneNote would receive rather than a preview guessed on this side
(`onenote_create_page` is the exception: a page that does not exist yet cannot be previewed, and
`onenote_delete_page` because deletion has nothing to return). Applying asks for confirmation, and a
non-interactive run counts as already approved.

## Transport constraints

These are not stylistic. Each one cost real debugging time and must stay as it is.

- **The script is never run with `-File`.** Windows PowerShell 5.1 decodes a BOM-less file as ANSI,
  which destroys every CJK literal. `index.ts` reads `bridge.ps1` as UTF-8 and hands it to a
  ~200-character `-EncodedCommand` bootstrap *through the request file*.
- **Paths never ride in environment variables.** WSL interop does not forward the Linux environment
  to Windows executables and ignores `WSLENV` in that direction, so the bootstrap carries the work
  directory instead.
- **The bridge cannot be sent through `-EncodedCommand` itself.** A Windows command line caps out
  near 32 K characters, and the script is longer than that once encoded.
- **Payloads travel through UTF-8 files, not arguments.** Page XML reaches 260 KB and image base64
  reached 5.4 MB in testing. Each call uses its own request/response pair, so parallel tool calls
  cannot clobber each other's files.
- **XPath uses `local-name()` instead of a namespace manager.** `XmlNameTable` **and**
  `XmlNamespaceManager` implement `IEnumerable`, so passing or returning one makes PowerShell
  silently unroll it into namespace prefixes and the namespace lookup fails with a confusing
  "cannot find an overload for SelectNodes".
- **Request fields are read through `Get-Field`, not property access.** A hashtable's property
  access falls through to the type's members, so an absent field named `remove` returns
  `Hashtable.Remove`'s overload list instead of `$null`. This produced an error message containing
  a method signature.
- **Function parameters that must accept `$null` are left untyped.** Declaring `[string]$newText`
  makes PowerShell convert a `$null` argument into `""`, which silently turned "leave this paragraph
  alone" into "replace its text with nothing".

## Writing into OneNote

All of the following is verified against the live client.

### objectID

New elements must be written **without** an `objectID`. OneNote rejects an id it did not issue with
`0x8004200E` (`hrPageObjectDoesNotExist`), and assigns ids itself for anything sent without one.
`ID` on `one:Outline` is not in the schema at all — the attribute is `objectID`.

### UpdatePageContent

The real signature is:

```
UpdatePageContent(string xml, DateTime dateExpectedLastModified, XMLSchema xsSchema, out string error)
```

- `xsSchema` must be **`2`** (xs2013) to match the namespace this bridge writes. `0` and `1` fail
  with `0x80042001`.
- Naming all four arguments keeps the error channel. PowerShell accepts fewer, but then OneNote's
  own refusals are invisible.
- `dateExpectedLastModified` is always `MinValue` ("do not check") — see the next section.

### The edit model

`one:OEChildren` is **authoritative for its children**: the list that is sent becomes the complete
child list, so a paragraph omitted from it is **deleted**. Meanwhile page elements that are not
mentioned at all (the title, other outlines) are preserved. Verified by experiment:

| Action | Result |
| --- | --- |
| Resend an outline with all paragraphs by objectID, one text changed | text changed in place, objectID kept, other outlines and the title untouched |
| Omit a paragraph in that resend | the omitted paragraph is deleted |
| Send a new paragraph with no objectID | added, OneNote assigns its id |
| Omit `Position`/`Size` for an existing outline | geometry preserved |
| Send an empty `one:OEChildren` | rejected: "cannot be empty according to the DTD/Schema" |

Therefore **the safe unit of edit is one whole outline, resent in full**, which is what
`onenote_edit` does: it groups the requested changes by owning outline, echoes back OneNote's own
XML (`OuterXml`) for every paragraph it is not changing — so styles, lists, tables and images
survive — and substitutes only the `<one:T>` of the paragraphs being edited. Paragraph XML must
never be hand-built by a caller.

### Rich text

`one:T` holds an **HTML-ish fragment inside CDATA**, with entities still escaped even inside CDATA.
Consequences both ways:

- **Reading** needs tag stripping *and* entity decoding, plus a manual numeric-reference pass:
  .NET's `HtmlDecode` silently skips astral-plane references such as `&#128640;`, so emoji would
  otherwise come back as literal text.
- **Writing** must escape `&`, `<` and `>` first (`New-TextCdata`). Otherwise a literal
  `<angles>` is parsed as a tag and disappears. OneNote does the same itself: `->` is stored as
  `-&gt;`.

### Tables

`one:Table` is a child of **`one:OE`**, never of `one:Outline`. `Table` is `Columns?` then `Row+`,
`one:Column` requires both `index` and `width` (so `Columns` is emitted only when widths are given),
and every `one:Cell` **must** contain an `OEChildren`. There is no `columnSpan`/`rowSpan` in the
schema at all.

### Images

`one:Data` with base64 is the supported import path — no callback object is involved. `format` must
match `auto|png|emf|jpg`, so JPEG is spelled **`jpg`**. Reading back never returns `Data`: OneNote
replaces it with a `one:CallbackID`, which is the evidence that the bits are really stored (the
model reports this as `embedded`). `format` is not echoed back. Without `width`/`height` OneNote
chooses the size. Verified working up to **5.4 MB of base64**.

## `lastModifiedTime` is not a concurrency token

This dictates the write design, and it cost two discarded implementations:

- It **does not advance when content is written through COM.** Three appends in a row left it at the
  page's creation second.
- `GetHierarchy` can report a **different value** than `GetPageContent` for the same page.

So comparing it refuses legitimate writes while detecting nothing. Both guards built on it were
removed during development: one refused a correct append with `stale` even though nothing had
changed, and feeding back the value just read protects nothing. Instead:

- appends are additive and cannot clobber a concurrent edit, so they need no token;
- `onenote_delete_page` guards on the **exact page name** (`expectName` is required);
- `lastModified` is reported as informational only.

## Not implemented

- Rewriting a paragraph **in place has since been solved** (`onenote_edit`); what remains missing is
  deleting a whole outline, and editing inside table cells by position (cells are reachable as
  ordinary paragraphs through their own objectIDs).
- Ink, `one:HTMLBlock` (xs2013 rich HTML fragments) and page-level `one:Image` positioning.
- The tools are OneNote-only. Anything outside COM's reach (Copilot pane, ink) would need a UIA layer.

## Testing

The transport can be exercised without Pi at all, which is the fastest loop: write a request JSON
into the work directory (`%TEMP%\pi-onenote`), run a tiny `-EncodedCommand` bootstrap that reads it
and `Invoke-Expression`s `bridge.ps1`, and read the response JSON back. Test suites that did this
while developing the extension covered page lifecycle, the full edit model, and tables/images
(14, 31 and 30 checks respectively), each creating and deleting its own probe page.
