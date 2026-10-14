#!/bin/sh
set -eu
seed-config.sh /home/tester/.hermes tester:tester
install -o tester -g tester -m 600 /testbed-keys/authorized_keys /home/tester/.ssh/authorized_keys
ssh-keygen -A >/dev/null
exec /usr/sbin/sshd -D -e
