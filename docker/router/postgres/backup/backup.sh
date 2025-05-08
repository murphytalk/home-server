#!/usr/bin/env bash
MYUID=1000
MYGID=1000

SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was relative symlink, resolve it relative to DIR
done
DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
DB_NAME=urphin 

backup(){
  BKFN="${DIR}/$1.sql.gz"
  if [ ! -e $BKFN ];then
    PGPASSWORD="java2" pg_dump  -U postgres -d $DB_NAME  | gzip > $BKFN
    chown $MYUID:$MYGID $BKFN
  fi
}

TM=$(date +"%Y-%m-%d")
backup "${DB_NAME}-${TM}"

TM=$(date +"%Y-%m-%d_%H-%M")
backup "${DB_NAME}-${TM}"


find $DIR -type f -regex ".*${DB_NAME}-[0-9][0-9][0-9][0-9].*_.*.gz" -mmin +60 -exec rm {} \;
find $DIR -type f -regex ".*${DB_NAME}-[0-9][0-9][0-9][0-9][^_]*gz"  -mtime +3 -exec rm {} \;
