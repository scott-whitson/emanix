#!/bin/bash
while true; do
    hour=$(date +%H)
    if [ "$hour" -ge 12 ]; then
        time="$(date '+%d %I:%M.')"
    else
        time="$(date '+%d %I:%M')"
    fi
    cal=$(cal | sed 's/\x20*$//' | sed ':a;N;$!ba;s/\n/\\n/g')
    full="$(date '+%A, %B %d, %Y')"
    echo "{\"text\": \"$time\", \"tooltip\": \"$full\\n\\n$cal\"}"
    sleep 30
done
