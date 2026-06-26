#!/bin/zsh

serial=$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')
newName="<Prefix>$serial"

/usr/sbin/scutil --set ComputerName "$newName"
/usr/sbin/scutil --set LocalHostName "$newName"
/usr/sbin/scutil --set HostName "$newName"
