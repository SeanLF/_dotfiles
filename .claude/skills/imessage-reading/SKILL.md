---
name: imessage-reading
description: Use when reading or analysing an iMessage conversation from Sean's Mac (a thread with one contact, a date range, "what did X and I talk about"). Covers filtering by contact with imessage-exporter 5.x, and trimming the export to ~30% of its size for LLM reading.
---

# Reading an iMessage conversation

`imessage-exporter` (5.x) does the hard part: decoding `attributedBody`, stickers,
edits, tapback association, threading, and merging one person's phone and email
threads into a single transcript via Contacts. Its **txt rendering** is what wastes
context: every threaded reply is written twice. Export with it, then trim.

Placeholders below: `NAME` is the contact's name, `+1XXXXXXXXXX` a phone handle,
`them@example.com` an email handle. Never write real handles or names into this file.

The terminal needs Full Disk Access (Messages and Contacts both sit behind it), and
the Bash call must run outside the sandbox, or every command fails with
`Operation not permitted`.

## Recipe

1. **Export, filtered to the person**, into a scratch dir:

   ```sh
   imessage-exporter -f txt -t 'NAME' -s 2026-01-01 -o "$SCRATCH/export" --no-progress
   ```

   `-t` takes contact names, numbers or emails, comma-separated. Any one of a
   person's addresses selects all of them, so one value is enough. Confirm the run
   prints `Filtering for N handles across M chatrooms`, where N counts _people_,
   not addresses. If N is higher than you expected, the name matched someone else
   too (see Gotchas); use a full name or a handle. Add `-e` for an end date. Omit
   `-c` unless you actually need attachment files copied.

2. **Pick the files.** The filter exports every chat the person is in, group chats
   included, plus an empty `orphaned.txt`. The 1:1 transcript is the file whose name
   has no comma. It is named after a single address (phone or email, whichever
   Messages picked as representative), not after the contact, so don't predict the
   filename; list the dir.

3. **Trim** (no deps, stdlib only):

   ```sh
   python3 ~/.claude/skills/imessage-reading/trim_imsg.py "$SCRATCH/export/+1XXXXXXXXXX.txt" -o trimmed.md
   ```

   Prints `N parsed, D duplicate-reply blocks, E empty, K kept`. Expect a 60 to 70% cut.
   With one input, order is left as-exported (replies nested under their parent).
   With several (a group chat plus the 1:1, or a person whose addresses 5.x could
   not merge), everything is sorted into one strictly chronological transcript and
   exact cross-file repeats are dropped.

4. **Negative-control the trim** before trusting it. A filter that silently eats
   messages reads exactly like a quiet conversation:

   ```sh
   command grep -c 'This message responded to an earlier message.' "$SCRATCH/export/+1XXXXXXXXXX.txt"  # == D
   sqlite3 ~/Library/Messages/chat.db "SELECT COUNT(*) FROM chat_message_join cmj
     JOIN message m ON m.ROWID=cmj.message_id
     WHERE cmj.chat_id IN (SELECT chj.chat_id FROM chat_handle_join chj JOIN handle h ON h.ROWID=chj.handle_id
       WHERE h.id COLLATE NOCASE IN ('+1XXXXXXXXXX','them@example.com')
       AND chj.chat_id IN (SELECT chat_id FROM chat_handle_join GROUP BY chat_id HAVING COUNT(*)=1))
     AND m.date/1000000000 + 978307200 >= unixepoch('2026-01-01')
     AND m.associated_message_type=0;"                                                              # ≈ K
   ```

   List _every_ address of the person in the `IN (...)`: the merged transcript holds
   all of them. `D` must equal the marker count exactly. `K` should land within
   ~0.2% of the DB count; the residue is `item_type != 0` announcements and
   empty-body rows. If `K` matches only one address's count, the merge didn't happen
   and the other address is in a separate file.

   Count through `chat_message_join`, **not** `message.handle_id`. Outgoing messages
   can carry `handle_id = 0`, and a handle join silently undercounts your own side of
   the conversation by thousands.

## Output format

`HH:MM S:` = Sean, `X:` = the other person's initial. `>` marks a threaded reply;
`(Mon D)` after `>` means that reply landed on a later day than its parent. Tapbacks
compress to `[♥S]`, `[hahaX]`, `[+1S]`. Attachments become `[img: NAME.HEIC]`.

## Gotchas

- **Name filters are case-sensitive substrings** of first, last and full name and of
  every address. A short first name catches other contacts whose names contain it,
  and their chats get exported too. An unmatched filter errors out
  (`does not match any participants`) instead of exporting everything as 4.x did.
- **The phone and email merge relies on Contacts.** 5.x merges addresses that sit on
  one Contacts card. It skips an address that is on several cards, and an address
  missing from Contacts stays a separate conversation. Check with step 4.
- **Every threaded reply is written twice.** Once indented under its parent, once at
  top level tagged `This message responded to an earlier message.` That duplication,
  plus read receipts and absolute attachment paths, is ~70% of the file. It comes from
  the txt template, not the data; reading `chat.db` directly has no duplication.
- **A parent's body is split around its inline replies.** Text after a reply thread
  still belongs to the parent message; the trimmer reattaches it by indentation.
- **Edited messages** embed a timestamp mid-body and a `Edited Ns later:` line; the
  trimmer keeps only the final text.
- **Attachment filenames can contain spaces**, so don't match them with `\S+`.
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
