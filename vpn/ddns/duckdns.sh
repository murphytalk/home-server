#!/usr/bin/env bash
echo url="https://www.duckdns.org/update?domains=murphytalk&token=cc60b3bc-555d-4c55-8634-db2d6ffa3568&ip=" | curl -k -o /tmp/duck.log -K -
