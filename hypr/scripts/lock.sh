#!/usr/bin/env bash

LOCKIMG="/tmp/lockscreen.png"

# Take screenshot of current desktop
grim "$LOCKIMG"

# Lock using that screenshot
hyprlock

