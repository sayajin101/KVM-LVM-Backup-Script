#!/bin/bash

lvc=$(which lvcreate);
lvr=$(which lvremove);

cat vm_backup.cfg | while read iName iVolumeGroup; do
	if [ -z "${iName}" ]; then echo -e "\nNo LVM Name or Volume Group Specified...Skipping\n"; continue; fi;
	if [ -z "${iVolumeGroup}" ]; then echo -e "\nNo LVM Name or Volume Group Specified...Skipping\n"; continue; fi;
	lv_path=$(lvscan | grep "`echo ${iVolumeGroup}\/${iName}`" | awk '{print $2}' | tr -d "'");
	if [ -z "${lv_path}" ]; then echo -e "\nNo such LVM exists: ${lv_path}\nCorrect path name in config file\n"; continue; fi;
	size=$(lvs ${lv_path} -o LV_SIZE --noheadings --units g --nosuffix | tr -d ' ');
	${lvc} -s --size=${size}G -n ${iName}_snap ${lv_path} && /bin/dd if=${lv_path}_snap bs=16MB | /bin/gzip -c | /bin/dd of=/backup/vms/${iVolumeGroup}-${iName}.`date +%Y-%m-%d-%H.%M.%S`.gz; ${lvr} -f ${lv_path}_snap;
done;