#!/usr/bin/env bash

PC="10.8.53.7"
PC_USER="admin"

printf "Prism Central password: " >&2
IFS= read -r -s PASS </dev/tty
printf "\n" >&2

if [[ -z "$PASS" ]]; then
    echo "ERROR: no password was entered." >&2
    exit 1
fi

for version in v4.0 v4.1 v4.2 v4.3; do
    code=$(curl --noproxy '*' -kS \
        --connect-timeout 10 \
        -u "${PC_USER}:${PASS}" \
        -o /dev/null \
        -w "%{http_code}" \
        "https://${PC}:9440/api/vmm/${version}/content/images")

    printf "%-6s HTTP %s\n" "$version" "$code"
done
