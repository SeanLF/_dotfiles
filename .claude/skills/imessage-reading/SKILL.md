---
name: imessage-reading
description: Use when reading or analysing an iMessage conversation from Sean's Mac (a thread with one contact, a date range, "what did X and I talk about"). Covers resolving a contact to a handle, exporting with imessage-exporter, and trimming the export to ~30% of its size for LLM reading.
---

# Reading an iMessage conversation

`imessage-exporter` does the hard part (decoding `attributedBody`, stickers, edits,
tapback association, threading). Its **txt rendering** is what wastes context: every
threaded reply is written twice. Export with it, then trim.

Placeholders below: `NAME` is the contact's first name, `+1XXXXXXXXXX` a phone handle,
`them@example.com` an email handle. Never write real handles or names into this file.

## Recipe

1. **Resolve the contact to handles.** Contact names do _not_ work as filters (see
   Gotchas). Query the AddressBook sources:

   ```sh
   for db in ~/Library/Application\ Support/AddressBook/Sources/*/AddressBook-v22.abcddb; do
     sqlite3 "$db" "SELECT r.ZFIRSTNAME, r.ZLASTNAME, p.ZFULLNUMBER FROM ZABCDRECORD r
       JOIN ZABCDPHONENUMBER p ON p.ZOWNER=r.Z_PK WHERE r.ZFIRSTNAME LIKE '%NAME%';" 2>/dev/null
     sqlite3 "$db" "SELECT r.ZFIRSTNAME, r.ZLASTNAME, e.ZADDRESS FROM ZABCDRECORD r
       JOIN ZABCDEMAILADDRESS e ON e.ZOWNER=r.Z_PK WHERE r.ZFIRSTNAME LIKE '%NAME%';" 2>/dev/null
   done | sort -u
   ```

2. **Export, scoped to every handle for that person**, into a scratch dir:

   ```sh
   imessage-exporter -f txt -t '+1XXXXXXXXXX,them@example.com' \
     -s 2026-01-01 -o "$SCRATCH/export" --no-progress
   ```

   Confirm the run prints `Filtering for N handles across M chatrooms`. Add `-e` for an
   end date. Omit `-c` unless you actually need attachment files copied.

3. **Trim** (no deps, stdlib only). Pass _every_ file the export produced. Apple
   splits one conversation across handles and the threads overlap in time, so a
   single file is half a conversation:

   ```sh
   python3 ~/.claude/skills/imessage-reading/trim_imsg.py "$SCRATCH/export/"*.txt -o trimmed.md
   ```

   Prints `N parsed, D duplicate-reply blocks, E empty, K kept`. Expect a 60 to 70% cut.
   With one input, order is left as-exported (replies nested under their parent);
   with several, everything is sorted into one strictly chronological transcript and
   exact cross-handle repeats are dropped.

4. **Negative-control the trim** before trusting it. A filter that silently eats
   messages reads exactly like a quiet conversation:

   ```sh
   command grep -c 'This message responded to an earlier message.' export/+1XXX.txt   # == D
   sqlite3 ~/Library/Messages/chat.db "SELECT COUNT(*) FROM message m
     JOIN handle h ON m.handle_id=h.ROWID WHERE h.id='+1XXXXXXXXXX'
     AND datetime(m.date/1000000000 + strftime('%s','2001-01-01'),'unixepoch') >= '2026-01-01'
     AND m.associated_message_type=0;"                                                  # ≈ K
   ```

   `D` must equal the marker count exactly. `K` should land within ~0.2% of the DB
   count; the residue is `item_type != 0` announcements and empty-body rows.

   Join through `chat_message_join`, **not** `handle`. Outgoing messages can carry
   `handle_id = 0` and a handle join silently undercounts your own side of the
   conversation by thousands.

## Output format

`HH:MM S:` = Sean, `X:` = the other person's initial. `>` marks a threaded reply;
`(Mon D)` after `>` means that reply landed on a later day than its parent. Tapbacks
compress to `[♥S]`, `[hahaX]`, `[+1S]`. Attachments become `[img: NAME.HEIC]`.

## Gotchas

- **`-t NAME` does not filter; it exports your entire message history.** Contact
  names never resolve (filenames come out as raw phone numbers), the filter matches
  nothing, and the tool falls back to exporting every conversation on the Mac. Only
  numbers and emails work. Watch for the `Filtering for N handles` line; if it's
  absent, you just dumped everything.
- **Every threaded reply is written twice.** Once indented under its parent, once at
  top level tagged `This message responded to an earlier message.` That duplication,
  plus read receipts and absolute attachment paths, is ~70% of the file. This is a
  rendering artifact of the txt template, not the data; reading `chat.db` directly has
  no duplication.
- **A parent's body is split around its inline replies.** Text after a reply thread
  still belongs to the parent message; the trimmer reattaches it by indentation.
- **Edited messages** embed a timestamp mid-body and a `Edited Ns later:` line; the
  trimmer keeps only the final text.
- **Attachment filenames can contain spaces**, so don't match them with `\S+`.
- **One person is usually two threads.** A contact with both a number and an Apple ID
  email gets two chats that run _concurrently_, not sequentially, often for months
  with thousands of messages on each side. Always export and trim all handles together.
- The export contains whatever was sent: **1Password share links, 2FA codes,
  addresses**. Don't echo credentials back when summarising, and keep exports and
  trimmed transcripts in the scratch dir, never in a repo.

## Alternative: an MCP server

Worth it only for **ad-hoc queries and relationship analytics**, not bulk transcript
reading. MCP returns JSON per message, which is heavier per message than the format
above (it just avoids the duplication).

- [`anipotts/imessage-mcp`](https://github.com/anipotts/imessage-mcp): 26 tools, all
  `readOnlyHint: true`, **cannot send**. `get_conversation`, `who_initiates`, `streaks`.
  The safest of the bunch, but was last pushed 2026-05-13.
- The `imessage-mcp` entry in Anthropic's `claude-plugins-community` marketplace is
  **not an Anthropic tool**. It resolves to `adelaidasofia/imessage-mcp` (2 stars, no
  licence) and it _can send_ via AppleScript. Listing ≠ endorsement.

Any of these needs Full Disk Access granted to the client. Granting a third-party
binary FDA plus send capability is a real standing risk for an agent; `imessage-exporter`
plus this trimmer is read-only and needs no persistent tool surface.
