#!/usr/bin/env bash
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was relative symlink, resolve it relative to DIR
done
DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
SCRIPT=$DIR/$(basename "$0")
DB_NAME=urphin 
echo run $SCRIPT 
if echo $SCRIPT | grep daily > /dev/null;then
  daily=y
  TM=$(date +"%Y-%m-%d")
  FNAME="daily-${DB_NAME}-${TM}"
else
  TM=$(date +"%Y-%m-%d_%H-%M")
  FNAME="${DB_NAME}-${TM}"
fi

PGPASSWORD="java2" pg_dump  -U postgres -d $DB_NAME  | gzip > "${DIR}/${FNAME}.sql.gz"

if [ -z "$daily" ];then
   find $DIR -type f -name "${DB_NAME}-*.gz" -mmin +60 -exec rm {} \;
else
   find $DIR -type f -name "daily-${DB_NAME}-*.gz" -mtime +7 -exec rm {} \;
fi
