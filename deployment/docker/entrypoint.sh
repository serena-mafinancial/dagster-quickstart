#!/bin/bash

if [ "$1" = "webserver" ]; then
    exec dagster-webserver -h 0.0.0.0 -p 3000
elif [ "$1" = "daemon" ]; then
    exec dagster-daemon run
elif [ "$1" = "user_code" ]; then
    exec dagster api grpc -h 0.0.0.0 -p 4000
else
    echo "Unknown command: $1"
    exit 1
fi