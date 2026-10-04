#!/bin/zsh
# Builds RemindersBridge.app, installs it with its LaunchAgent and the `rem` client.
set -e
cd ${0:A:h}/..
identity="Apple Development: Dulanga JAYAWARDENA (5D2G58P6ZB)"
app=~/Applications/RemindersBridge.app
label=com.dullybot.reminders-bridge
plist=~/Library/LaunchAgents/$label.plist

swift build -c release --product reminders
rm -rf $app && mkdir -p $app/Contents/MacOS
cp bridge/Info.plist $app/Contents/
cp .build/release/reminders $app/Contents/MacOS/
swiftc -O bridge/main.swift -o $app/Contents/MacOS/RemindersBridge
codesign -f -o runtime -s $identity -i $label.cli $app/Contents/MacOS/reminders
codesign -f -o runtime -s $identity $app

mkdir -p ~/.reminders-bridge/{queue,out}
cat > $plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$label</string>
	<key>ProgramArguments</key><array><string>$app/Contents/MacOS/RemindersBridge</string></array>
	<key>AssociatedBundleIdentifiers</key><string>$label</string>
	<key>QueueDirectories</key><array><string>$HOME/.reminders-bridge/queue</string></array>
	<key>ThrottleInterval</key><integer>1</integer>
</dict>
</plist>
EOF
launchctl bootout gui/$(id -u)/$label 2>/dev/null || true
launchctl bootstrap gui/$(id -u) $plist
install -m 755 bridge/rem ~/.local/bin/rem
