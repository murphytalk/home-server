#!/usr/bin/env bash
ip=$(curl -s ifconfig.me)
echo url="http://api.dynu.com/nic/update?myip=$ip&username=murphytalk&password=ed92bc6e1c8fb2eea45bda87497727d1" | curl -k -o /tmp/dynu.log -K -
