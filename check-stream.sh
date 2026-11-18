#!/bin/bash
URL=${1:-rtsp://localhost:8554/cam}	# which stream to check

# 1. Run the check, keep everything it says (errors too)
OUT=$(timeout 5 ffprobe -v error -analyzeduration 1000000 -rtsp_transport udp "$URL" 2>&1)

# 2. Remember how it ended
CODE=$?

#3. Go down the list until one matches
if [[ $CODE -eq 0 ]]; then	# worked?
    echo "UP"
    exit 0
elif [[ $CODE -eq 124 ]]; then	# timeout killed it?
	echo "DOWN: no answer (timed out)"
    exit 1
elif [[ "$OUT" == *"404"* ]]; then	# name lookup failed?
    echo "DOWN: no stream on the path"
    exit 1
elif [[ "$OUT" == *"resolve"* ]]; then	# name lookup failed?
    echo "DOWN: bad hostname"
    exit 1
else
    echo "DOWN: uknown error: $OUT"
    exit 1    
fi    
