#!/bin/bash

[ ! -f kvm-lvm-backup.cfg ] && { echo -e "\nConfig file not found, creating it\nPlease add your LVMs to the config file becore continuing\n" && touch kvm-lvm-backup.cfg && exit 1; };
[ ! -s kvm-lvm-backup.cfg ] && { echo -e "\nkvm-lvm-backup.cfg is empty, please fill in your LVM details" && exit 1; };

lvc=$(which lvcreate);
lvr=$(which lvremove);
remotePort="22";
remoteUser="root";
remoteAddress="backup.server.com";

cat kvm-lvm-remote-backup.cfg | while read iName iVolumeGroup iRemoteMount iCompressionLocation; do
  # Check if backup file system is mounted on remote server if not then try to mount the backup volume
  mountCheck=$(ssh -p ${remotePort} ${remoteUser}@${remoteAddress} "mount | grep -qs '${iRemoteMount}' && echo 'mounted' || { mount ${iRemoteMount} > /dev/null 2>&1 && [ ${?} -eq 0 ] && echo 'mount successful' || echo 'something went wrong'; }";);

  # Backup volume remote mount check result check
  [ "${mountCheck}" == "something went wrong" ] && { echo "Remote Server backup mount is not mounted & mount attemtp failed...exiting && exit 1; };

	if [ -z "${iName}" ]; then echo -e "\nNo LVM Name, Volume Group, Remote Mount or Compression Location Specified...Skipping\n"; continue; fi;
	if [ -z "${iVolumeGroup}" ]; then echo -e "\nNo LVM Name, Volume Group, Remote Mount or Compression Location Specified...Skipping\n"; continue; fi;
	if [ -z "${iRemoteMount}" ]; then echo -e "\nNo LVM Name, Volume Group, Remote Mount or Compression Location Specified...Skipping\n"; continue; fi;
	if [ -z "${iCompressionLocation}" ]; then echo -e "\nNo LVM Name, Volume Group, Remote Mount or Compression Location Specified...Skipping\n"; continue; fi;
	lv_path=$(lvscan | grep "`echo ${iVolumeGroup}\/${iName}`" | awk '{print $2}' | tr -d "'");
	if [ -z "${lv_path}" ]; then echo -e "\nNo such LVM exists: ${lv_path}\nCorrect path name in config file\n"; continue; fi;
	size=$(lvs ${lv_path} -o LV_SIZE --noheadings --units g --nosuffix | tr -d ' ');
	if [ "${iCompressionLocation}" == "remote" ]; then
	  ${lvc} -s --size=${size}G -n ${iName}_snap ${lv_path} && /bin/dd if=${lv_path}_snap bs=16MB | ssh -p ${remotePort} ${remoteUser}@${remoteAddress} "/bin/gzip -c | /bin/dd of=/backup/vms/${iVolumeGroup}-${iName}.`date +%Y-%m-%d-%H.%M.%S`.gz; ${lvr} -f ${lv_path}_snap";
	elif [ "${iCompressionLocation}" == "local" ]; then
	    ${lvc} -s --size=${size}G -n ${iName}_snap ${lv_path} && /bin/dd if=${lv_path}_snap bs=16MB | /bin/gzip -c | ssh -p ${remotePort} ${remoteUser}@${remoteAddress} "/bin/dd of=/backup/vms/${iVolumeGroup}-${iName}.`date +%Y-%m-%d-%H.%M.%S`.gz; ${lvr} -f ${lv_path}_snap";
	fi;
done;
