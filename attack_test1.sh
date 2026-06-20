#!/bin/bash

while true; do
    python attack_test.py &

    for i in {1..8}; do
        ssh -o StrictHostKeyChecking=no \
            -o ConnectTimeout=2 \
            testuser@20.203.151.95
    done

    sleep 2
done