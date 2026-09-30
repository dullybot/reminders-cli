# reminders-cli

A simple CLI for interacting with macOS reminders. Requires macOS 14 or later.

## Usage:

#### Show all lists

```
$ reminders show-lists
Soon
Eventually
```

#### Show reminders on a specific list

```
$ reminders show Soon
0 Write README
1 Ship reminders-cli
```

#### Complete an item on a list

```
$ reminders complete Soon 0
Completed 'Write README'
$ reminders show Soon
0 Ship reminders-cli
```

#### Undo a completed item

```
$ reminders show Soon --only-completed
0 Write README
$ reminders uncomplete Soon 0
Uncompleted 'Write README'
$ reminders show Soon
0 Write README
```

#### Edit an item on a list

```
$ reminders edit Soon 0 Some edited text
Updated reminder 'Some edited text'
$ reminders edit Soon 0 --due-date "tomorrow 9am"
Updated reminder 'Some edited text'
$ reminders edit Soon 0 --clear-due-date --clear-notes
Updated reminder 'Some edited text'
$ reminders show Soon
0 Ship reminders-cli
1 Some edited text
```

#### Delete an item on a list

```
$ reminders delete Soon 0
Deleted 'Write README'
$ reminders show Soon
0 Ship reminders-cli
$ reminders show Soon --only-completed
0 Old task
$ reminders delete Soon 0 --only-completed
Deleted 'Old task'
```

#### Add a reminder to a list

```
$ reminders add Soon Contribute to open source
$ reminders add Soon Go to the grocery store --due-date "tomorrow 9am"
$ reminders add Soon Something really important --priority high
$ reminders show Soon
0: Ship reminders-cli
1: Contribute to open source
2: Go to the grocery store (in 10 hours)
3: Something really important (priority: high)
```

#### Repeat, alarms and URLs

`--alarm` takes a date, or an offset from the due date such as `-15m`, `-1h`,
`-2d` or `+30m`, and can be passed more than once. `edit` also takes
`--clear-repeat`, `--clear-alarms` and `--url ""`.

```
$ reminders add Soon Pay rent --due-date "2026-10-01 9am" --repeat monthly
$ reminders add Soon Standup --due-date "tomorrow 10am" --repeat weekly --repeat-interval 2 --repeat-end 2026-12-31
$ reminders add Soon Call mom --due-date "tomorrow 6pm" --alarm -15m --alarm "tomorrow 9am"
$ reminders add Soon Read this --url https://example.com
$ reminders show Soon
0: Pay rent (in 1 day) (repeats every month) (alarms: in 1 day)
1: Standup (in 1 day) (repeats every 2 weeks) (alarms: in 1 day)
2: Call mom (in 1 day) (alarms: in 1 day, in 1 day)
3: Read this <https://example.com>
```

#### Flags, tags, subtasks and assignees

EventKit doesn't expose these, so they use Apple's private ReminderKit
framework and may stop working after a macOS update. Assignees need a list
shared through iCloud.

```
$ reminders add Soon Ship it --flag --tag work --tag release
$ reminders add Soon Write changelog --parent 0
$ reminders edit Soon 1 --assign "Sam"
$ reminders show Soon
0: Ship it #release #work (flagged)
1: Write changelog (assigned to Sam) (subtask of 'Ship it')
$ reminders edit Soon 1 --unnest --unassign
$ reminders edit Soon 0 --unflag --remove-tag release
```

#### Show reminders due on or by a date

```
$ reminders show-all --due-date today
1: Contribute to open source (in 3 hours)
$ reminders show-all --due-date today --include-overdue
0: Ship reminders-cli (2 days ago)
1: Contribute to open source (in 3 hours)
$ reminders show-all --due-date 2025-02-16
1: Contribute to open source (in 3 hours)
$ reminders show Soon --due-date today --include-overdue
0: Ship reminders-cli (2 days ago)
1: Contribute to open source (in 3 hours)
```

#### Create a list

`--source` takes a source title or, when several share a title, the
identifier printed next to it.

```
$ reminders new-list Groceries
Created new list 'Groceries'!
$ reminders new-list Work --source iCloud
Created new list 'Work'!
```

#### See help for more examples

```
$ reminders --help
$ reminders show -h
$ reminders --version
```

## Installation:

#### With [Homebrew](http://brew.sh/)

```
$ brew install keith/formulae/reminders-cli
```

#### From GitHub releases

Download the latest release from
[here](https://github.com/keith/reminders-cli/releases)

```
$ tar -zxvf reminders.tar.gz
$ mv reminders /usr/local/bin
$ rm reminders.tar.gz
```

#### Building manually

This requires a recent Xcode installation.

```
$ cd reminders-cli
$ make build-release
$ cp .build/apple/Products/Release/reminders /usr/local/bin/reminders
```
