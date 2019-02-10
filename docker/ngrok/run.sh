#!/bin/sh
. /data/ngrok.inc
HOST=`ifconfig eth0 |grep 'inet addr'|sed 's/.*addr:\(.*\)  Bcast.*$/\1/g'`
sed -i "s/#AUTH#/$AUTH/g" /root/ngrok.yml
sed -i "s/#ADDR#/$HOST/g" /root/ngrok.yml
exec /bin/ngrok start --all --config=/root/ngrok.yml
