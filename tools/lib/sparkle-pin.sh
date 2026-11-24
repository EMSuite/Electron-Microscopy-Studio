#!/bin/sh
# The Sparkle the website download links (#761), in one place. tools/build-sparkle.sh builds Vendor/Sparkle from this tag and
# checks the clone is this commit; tools/appcast.sh takes sign_update from this tag's official Swift Package Manager zip, held to
# the checksum Sparkle's own Package.swift states for it at this tag (the binary SwiftPM fetched before #761). NOTICE names the
# tag and commit, and tools/run-tests.sh inventory holds Vendor/Sparkle/build-info.txt to them.
SPARKLE_TAG=2.10.1
SPARKLE_COMMIT=ab7d71291238df6e0492143b120c9b696a35f603
SPARKLE_SPM_ZIP_SHA256=4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a
