#!/bin/sh
# Build the flashable module zip.
set -eu
cd "$(dirname "$0")"

OUT=../A2DP-Sink-OnePlus9RT-v1.3.2.zip
rm -f "$OUT"

chmod 644 module.prop README.md
chmod 755 ./*.sh

zip -9r "$OUT" \
    module.prop \
    customize.sh \
    post-fs-data.sh \
    service.sh \
    action.sh \
    uninstall.sh \
    common.sh \
    README.md \
    LICENSE \
    webroot

echo "Built: $(cd .. && pwd)/$(basename "$OUT")"
