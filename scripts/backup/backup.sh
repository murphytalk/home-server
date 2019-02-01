#!/usr/bin/env bash
ROOT=`dirname $0`
BACKUP_DIR="$HOME/Backup2Gdrive"

find $BACKUP_DIR -name "*.bz2" -atime +7 -exec rm -f {} \;

# task protocol
# a task must export the following env var
#  - DIR   : folder which holds the files to be backed up
#  - FILES : a list of files relative to DIR
for i in $ROOT/tasks/*.tsk;do
    if [ -f $i ];then
        . $i
        [ -z "$DIR" ] && echo "task $task didn't export DIR !!" && exit 1
        [ -z "$FILES" ] && echo "task $task didn't export FILES !!" && exit 1
        task=$(basename $i | sed 's/\(.*\)\.tsk/\1/g')
        [ ! -d $BACKUP_DIR/$task ] && mkdir $BACKUP_DIR/$task
        pushd $DIR > /dev/null
        echo Backing up $task ,files : $FILES
        tar cfj $BACKUP_DIR/$task/${task}-`date +%Y%m%d`.tar.bz2 $FILES
        popd > /dev/null
    fi
done

which rclone && rclone ls tank:/backup
if [ $? -eq 0 ];then
	rclone sync $BACKUP_DIR tank:/backup
else
	echo rclone not installed or tank:/backup does not exist.
fi

