# reminders-cli

A simple CLI for interacting with OS X reminders.

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
$ reminders edit Soon 0 --clear-due-date
Updated reminder 'Some edited text'
$ reminders edit Soon 0 --clear-notes
Updated reminder 'Some edited text'
$ reminders edit Soon 0 --priority high
Updated reminder 'Some edited text'
$ reminders show Soon
0 Ship reminders-cli
1 Some edited text
```

#### Delete an item on a list

```
$ reminders delete Soon 0
Completed 'Write README'
$ reminders show Soon
0 Ship reminders-cli
```

Pass the same `--only-completed` or `--include-completed` flag you used with
`show` so the index matches what it printed:

```
$ reminders show Soon --only-completed
0 Write README
$ reminders delete Soon 0 --only-completed
Deleted 'Write README'
```

#### Add a reminder to a list

```
$ reminders add Soon Contribute to open source
$ reminders add Soon Go to the grocery store --due-date "tomorrow 9am"
$ reminders add Soon Something really important --priority high
$ reminders add Soon Take the bread out --due-date "in 20 minutes"
$ reminders add Soon Read this --url https://example.com
$ reminders show Soon
0: Ship reminders-cli
1: Contribute to open source
2: Go to the grocery store (in 10 hours)
3: Something really important (priority: high)
4: Read this <https://example.com>
```

URLs are stored through EventKit's `url` field, which Reminders.app may not display. Use
`edit --url ""` to remove one.

#### Repeat a reminder

```
$ reminders add Soon Pay rent --due-date "2026-10-01 9am" --repeat monthly
$ reminders add Soon Standup --due-date "tomorrow 10am" --repeat weekly --repeat-interval 2 --repeat-end 2026-12-31
$ reminders edit Soon 0 --clear-repeat
```

#### Add alarms

`--alarm` takes a date, or an offset from the due date such as `-15m`, `-1h`,
`-2d` or `+30m`, and can be passed more than once. These are added alongside
the alarm a due time already gets. `edit` also takes `--clear-alarms`.

```
$ reminders add Soon Call mom --due-date "tomorrow 6pm" --alarm -15m --alarm "tomorrow 9am"
$ reminders show Soon
0: Call mom (in 1 day) (alarms: in 1 day, in 1 day, in 1 day)
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

#### See help for more examples

```
$ reminders --help
$ reminders show -h
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
