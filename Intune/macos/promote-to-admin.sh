#!/bin/bash

# Enable verbose output for Intune debugging
set -x

# Detect the currently logged-in user (reliable on modern macOS)
loggedInUser=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')

# Check if the user exists and is not already an admin
if [ -z "$loggedInUser" ] || [ "$loggedInUser" == "root" ] || [ "$loggedInUser" == "_windowserver" ]; then
    echo "No valid logged-in user detected or invalid user. Exiting."
    exit 1
fi

# Verify user exists in local directory
if ! dscl . -read /Users/"$loggedInUser" >/dev/null 2>&1; then
    echo "User $loggedInUser not found in local directory. Exiting."
    exit 1
fi

# Check if already in admin group (with local node)
if /usr/sbin/dseditgroup -o checkmember -n /Local/Default -m "$loggedInUser" admin >/dev/null 2>&1; then
    echo "$loggedInUser is already an admin. No changes needed."
    exit 0
else
    # Add to admin group (with local node)
    /usr/sbin/dseditgroup -o edit -n /Local/Default -a "$loggedInUser" -t user admin
    if [ $? -eq 0 ]; then
        echo "Successfully promoted $loggedInUser to admin."
        # Verify
        groups "$loggedInUser"
        exit 0
    else
        echo "Failed to promote $loggedInUser to admin. Error code: $?"
        exit 1
    fi
fi