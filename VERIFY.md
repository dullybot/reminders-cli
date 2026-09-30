# Verifying the macos27-refresh branch

Run these after Reminders access has been granted to the terminal or binary.
Everything below uses a throwaway list, `CLI Test`, and deletes it at the end.
Relative times such as "in 1 day" depend on when you run the commands.

```sh
cd ~/reminders-cli
swift build -c release
R=.build/release/reminders
```

## 0. Access, help and version (bug 3, #73, #75)

Run these **before** granting access, on a machine where the CLI has never
asked:

| Command | Expected |
| --- | --- |
| `$R --help` | Usage text. No permission prompt, no `countOfStores` log line. |
| `$R --version` | `2.6.0`. No prompt. |
| `$R --generate-completion-script zsh \| head -1` | `#compdef reminders`. No prompt. |
| `$R show-lists` | The macOS Reminders permission prompt appears (first command that needs access). Denying prints `Error: you need to grant reminders access` and exits 1. |

After granting access:

| Command | Expected |
| --- | --- |
| `$R show-lists 2>&1 \| grep -c countOfStores` | `0` (#75: no stray EventKit log line). |

## 1. Setup and new-list (#111)

| Command | Expected |
| --- | --- |
| `$R new-list "CLI Test"` | `Created new list 'CLI Test'!`, or, with several reminder accounts, `Multiple sources were found...` with one `  <title> (<identifier>)` line per account that holds reminder lists. Only sources with reminder lists are listed, so an iCloud calendar-only source never appears. |
| `$R new-list "CLI Test" --source iCloud` | `Created new list 'CLI Test'!` even when two sources are titled `iCloud` (#111). |
| `$R new-list "CLI Test 2" --source <identifier from above>` | `Created new list 'CLI Test 2'!` |
| `$R show-lists` | Includes `CLI Test`. |

Delete `CLI Test 2` in Reminders.app.

## 2. Debug print and force unwraps (bugs 1, 2)

| Command | Expected |
| --- | --- |
| `$R add "CLI Test" First` then `$R complete "CLI Test" 0` | Exactly one line: `Completed 'First'`. No `["First", ...]` array printed before it. |
| `$R uncomplete "CLI Test" 0` | `Uncompleted 'First'` |
| `$R add "CLI Test" Second --due-date tomorrow` then `$R show "CLI Test" --sort due-date` | `Second` first, `First` (no due date) last, no crash. |
| `$R show "CLI Test" --sort creation-date --sort-order descending` | `Second` before `First`, no crash. |

## 3. Predicates, shared store (item 5)

| Command | Expected |
| --- | --- |
| `$R show "CLI Test"` | `0: First`, `1: Second (in 1 day)`. |
| `$R show "CLI Test" --only-completed` | Empty. |
| `$R show-all --due-date tomorrow` | Lists `CLI Test: <n>: Second (in 1 day)` and other lists' reminders due tomorrow, nothing without a due date. |
| `$R show-all --due-date today --include-overdue` | Only reminders due today or earlier. |

## 4. Relative dates (#101)

| Command | Expected |
| --- | --- |
| Any time after 8am: `$R add "CLI Test" Weekend --due-date "in 2 days 8am"` then `$R show "CLI Test"` | `Weekend (in 2 days)`, never `in 1 day`, even though fewer than 48 hours remain. |
| `$R add "CLI Test" Later --due-date "today 11pm"` then `$R show "CLI Test"` | `Later (in N hours)` (same day keeps hour/minute precision). |

## 5. Completed reminders can be deleted (#95)

| Command | Expected |
| --- | --- |
| `$R complete "CLI Test" 0` (completes `First`) | `Completed 'First'` |
| `$R show "CLI Test" --only-completed` | `0: First` |
| `$R delete "CLI Test" 0 --only-completed` | `Deleted 'First'` |
| `$R show "CLI Test" --include-completed` | `First` gone. |
| `$R delete "CLI Test" 0 --only-completed --include-completed` | `Error: Cannot specify both --include-completed and --only-completed` |

## 6. Empty notes (#85)

| Command | Expected |
| --- | --- |
| `$R add "CLI Test" Noted --notes "some body"` then `$R show "CLI Test"` | `Noted (some body)` |
| `$R edit "CLI Test" <index of Noted> --clear-notes` | `Updated reminder 'Noted'`; `show` prints `Noted` with no `( )`. Reminders.app shows no notes. |
| `$R edit "CLI Test" <index> --notes "x"` then `$R edit "CLI Test" <index> --notes ""` | Both succeed; notes removed again. |
| `$R add "CLI Test" Empty --notes ""` | Succeeds; `show` prints `Empty` without `()`. |
| `$R add "CLI Test" Bad --notes=""` | `Error: Missing value for '--notes <notes>'` (ArgumentParser limitation; use `--notes ""` or `--clear-notes`). |

## 7. Repeat (#104)

| Command | Expected |
| --- | --- |
| `$R add "CLI Test" Rent --due-date "tomorrow 9am" --repeat monthly` | `Added 'Rent' to 'CLI Test'` |
| `$R add "CLI Test" Standup --due-date "tomorrow 10am" --repeat weekly --repeat-interval 2 --repeat-end 2027-01-01` | Added. |
| `$R show "CLI Test"` | `Rent (in 1 day) (repeats every month) ...` and `Standup (in 1 day) (repeats every 2 weeks) ...` |
| `$R show "CLI Test" -f json` | `Standup` has `"recurrence" : [ { "frequency" : "weekly", "interval" : 2, "endDate" : "2027-01-01T..." } ]` |
| `$R add "CLI Test" X --repeat daily` | `Error: --repeat requires --due-date` |
| `$R add "CLI Test" X --due-date today --repeat hourly` | Error listing the valid values (no hourly; see notes). |
| `$R edit "CLI Test" <index of Rent> --clear-repeat` | Updated; `show` no longer prints `(repeats ...)`. |

**Reminders.app:** open `Standup` > info (i). *Repeat* shows *Custom: Every 2 weeks*, *End Repeat* shows 1 Jan 2027. `Rent` shows *Monthly* before `--clear-repeat` and *Never* after.

## 8. Alarms (item 7)

| Command | Expected |
| --- | --- |
| `$R add "CLI Test" Call --due-date "tomorrow 6pm" --alarm -15m --alarm -1h` | Added. |
| `$R show "CLI Test"` | `Call (in 1 day) (alarms: in 1 day, in 1 day, in 1 day)` (due-time alarm plus 5:45pm and 5pm). |
| `$R show "CLI Test" -f json` | `Call` has `"alarms"` with three ISO dates: tomorrow 18:00, 17:45 and 17:00 local time. |
| `$R add "CLI Test" Soon --due-date "today 11pm" --alarm "in 2 minutes"` | Added; a notification for `Soon` fires ~2 minutes later. |
| `$R add "CLI Test" NoDue --alarm -15m` | `Error: Relative --alarm offsets require --due-date` |
| `$R edit "CLI Test" <index of Call> --clear-alarms` | Updated; `show` has no `(alarms: ...)`. |
| `$R edit "CLI Test" <index of Call> --alarm +30m` | Updated; JSON `alarms` has tomorrow 18:30. |

**Reminders.app:** the notification for `Soon` appears in Notification Center.
Reminders.app's info panel only shows the due date ("Remind me") and at most one
*Early Reminder*; additional EventKit alarms may not be listed there, so the
JSON output and the fired notification are the proof.

## 9. URL (item 8)

| Command | Expected |
| --- | --- |
| `$R add "CLI Test" Read --url https://example.com/a` | Added. |
| `$R show "CLI Test"` | `Read <https://example.com/a>` |
| `$R show "CLI Test" -f json` | `"url" : "https://example.com/a"` |
| `$R edit "CLI Test" <index of Read> --url ""` | Updated; URL gone from `show`. |
| `$R add "CLI Test" X --url "not a url"` | `Error: --url must be an absolute URL such as https://example.com` |

**Reminders.app:** `Read` shows the URL (link preview) under the title before the
`--url ""` edit and not after. If the link only shows up in JSON but not in
Reminders.app, the ReminderKit URL attachment failed; report it.

## 10. Flagged (item 9)

| Command | Expected |
| --- | --- |
| `$R add "CLI Test" Important --flag` | Added. |
| `$R show "CLI Test"` | `Important (flagged)` |
| `$R show "CLI Test" -f json` | `Important` has `"flagged" : true`; every other reminder has `"flagged" : false` and `"tags" : [ ]`. |
| `$R edit "CLI Test" <index> --unflag` | Updated; no `(flagged)`. |

**Reminders.app:** `Important` shows the orange flag and appears in the *Flagged* smart list; after `--unflag` it does neither.

## 11. Tags (#74)

| Command | Expected |
| --- | --- |
| `$R add "CLI Test" Tagged --tag work -t "#home"` | Added. |
| `$R show "CLI Test"` | `Tagged #home #work` |
| `$R edit "CLI Test" <index> --tag work --tag urgent` | Updated; `#home #urgent #work` (no duplicate `#work`). |
| `$R edit "CLI Test" <index> --remove-tag home` | `#urgent #work` |
| `$R edit "CLI Test" <index> --clear-tags` | No tags. |

**Reminders.app:** `Tagged` shows `#home #work` chips, the tags appear in the sidebar *Tags* section, and clicking `#work` lists it.

## 12. Subtasks (#97)

| Command | Expected |
| --- | --- |
| `$R add "CLI Test" Project` then note its index P | Added. |
| `$R add "CLI Test" Step one --parent P` | Added. |
| `$R edit "CLI Test" <index of Tagged> --parent P` | Updated. |
| `$R show "CLI Test"` | `Step one (subtask of 'Project')`, `Tagged (subtask of 'Project')` |
| `$R show "CLI Test" -f json` | Both have `"parentId"` equal to `Project`'s `externalId`. |
| `$R edit "CLI Test" <index of Step one> --unnest` | Updated; no `(subtask of ...)`. |

**Reminders.app:** `Project` shows a disclosure triangle with `Step one` and `Tagged` indented beneath it; after `--unnest`, `Step one` is top level again.

## 13. Assignee (item 9, needs iCloud)

Needs an iCloud account and a list shared with at least one other person. Run
against that list (`Shared` below) instead of `CLI Test`.

| Command | Expected |
| --- | --- |
| `$R add Shared Task --assign "Nobody"` | `Failed to save reminder with error: no one named 'Nobody' shares this list, choose one of: <names>` (or `the list isn't shared`). |
| `$R edit Shared <index> --assign "<name or email from that list>"` | Updated. |
| `$R show Shared` | `Task (assigned to <name>)` |
| `$R edit Shared <index> --unassign` | Updated; no `(assigned to ...)`. |

**Reminders.app:** the reminder shows the assignee's avatar/initials; the other
person sees it in their *Assigned to Me* list.

## 14. ReminderKit failure mode

| Command | Expected |
| --- | --- |
| `swift test` (with Xcode) or the CLT command in the report | `runtimeHasEverythingTheBridgeUses` passes, i.e. every private class/selector exists on this macOS. |

If ReminderKit rejects the process (for example it requires an entitlement),
`show` still works without the Reminders.app-only fields, and `--flag`, `--tag`,
`--parent`, `--assign` fail with `Failed to ... error: ReminderKit ...` rather
than crashing. Record the exact message.

## Cleanup

Delete the `CLI Test` list in Reminders.app.
