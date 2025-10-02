#!/bin/bash
# Jenkins worker setup

set -e

echo "Installing dependencies..."
apt-get update -qq
apt-get install -y \
    debootstrap \
    debian-archive-keyring \
    jq \
    dpkg-dev \
    gnupg \
    curl \
    shellcheck \
    qemu-user-static

echo "Setup complete"
