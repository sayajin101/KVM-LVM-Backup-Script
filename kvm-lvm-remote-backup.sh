#!/bin/bash

#--========================================--#
# Set Varibles			       #
# Only Change the below varibles you need to #
#--========================================--#
remotePort="22";
remoteUser="root";
remoteAddress="backup.server.com";
#--========================================--#

configFile="kvm-lvm-remote-backup.cfg";
[ ! -f ${configFile} ] && { echo -e "\nConfig file not found, creating it\nPlease add your LVMs to the config file becore continuing\n" && touch ${configFile} && exit 1; };
[ ! -s ${configFile} ] && { echo -e "\n${configFile} is empty, please fill in your LVM details\n" && exit 1; };

lvc=$(which lvcreate);
lvr=$(which lvremove);

scriptPath=$(dirname "${BASH_SOURCE[0]}");

# Check Folder Structure
[ ! -d "${scriptPath}/key" ] || [ ! -d "${scriptPath}/logs" ] && mkdir -p "${scriptPath}"/{key,logs};

# Check if ssh key exists
[ ! -f "${scriptPath}/key/lvm-backup" ] && { ssh-keygen -b 4096 -q -t rsa -N "" -C "Remote KVM LVM Backups" -f "${scriptPath}/key/lvm-backup" && chmod 644 ${scriptPath}/key/lvm-backup* && echo -e "\nSSH Key has been created in ${scriptPath}/key called lvm-backup.pub\nYou must copy the key to your remote server.\nSSH key copy command: cat ${scriptPath}/key/lvm-backup.pub | ssh user@hostname 'cat >> .ssh/authorized_keys'\n" && exit 1; };

cat ${configFile} | grep -v '^#' | while read iName iVolumeGroup iRemotePath iCompressionLocation iRemoteStorgeType i; do
	if [ -z "${iName}" ]; then echo -e "\nNo LVM Name, Volume Group, Remote Mount or Compression Location Specified...Skipping\n"; continue; fi;
	if [ -z "${iVolumeGroup}" ]; then echo -e "\nNo LVM Name, Volume Group, Remote Mount or Compression Location Specified...Skipping\n"; continue; fi;
	if [ -z "${iRemotePath}" ]; then echo -e "\nNo LVM Name, Volume Group, Remote Mount or Compression Location Specified...Skipping\n"; continue; fi;
	if [ -z "${iCompressionLocation}" ]; then echo -e "\nNo LVM Name, Volume Group, Remote Mount or Compression Location Specified...Skipping\n"; continue; fi;
	if [ -z "${iRemoteStorgeType}" ]; then echo -e "\nNo LVM Name, Volume Group, Remote Mount or Compression Location Specified...Skipping\n"; continue; fi;

	if [ "${iRemoteStorgeType}" == "mounted" ]; then
		# Check if backup file system is mounted on remote server if not then try to mount the backup volume
		mountCheck=$(ssh -p ${remotePort} ${remoteUser}@${remoteAddress} "mount | grep -qs '${iRemotePath}' && echo 'mounted' || { mount ${iRemotePath} > /dev/null 2>&1 && [ ${?} -eq 0 ] && echo 'mount successful' || echo 'something went wrong'; }";);

		# Backup volume remote mount check result check
		[ "${mountCheck}" == "something went wrong" ] && { echo "Remote Server backup mount is not mounted & mount attemtp failed...exiting" && exit 1; };
	fi;

	lv_path=$(lvscan | grep "`echo ${iVolumeGroup}\/${iName}`" | awk '{print $2}' | tr -d "'");
	if [ -z "${lv_path}" ]; then echo -e "\nNo such LVM exists: ${lv_path}\nCorrect path name in config file\n"; continue; fi;
	size=$(lvs ${lv_path} -o LV_SIZE --noheadings --units g --nosuffix | tr -d ' ');
	if [ "${iCompressionLocation}" == "remote" ]; then
		${lvc} -s --size=${size}G -n ${iName}_snap ${lv_path} && /bin/dd if=${lv_path}_snap bs=16MB | ssh -p ${remotePort} ${remoteUser}@${remoteAddress} "/bin/gzip -c | /bin/dd of=/backup/vms/${iVolumeGroup}-${iName}.`date +%Y-%m-%d-%H.%M.%S`.gz; ${lvr} -f ${lv_path}_snap";
	elif [ "${iCompressionLocation}" == "local" ]; then
		${lvc} -s --size=${size}G -n ${iName}_snap ${lv_path} && /bin/dd if=${lv_path}_snap bs=16MB | /bin/gzip -c | ssh -p ${remotePort} ${remoteUser}@${remoteAddress} "/bin/dd of=/backup/vms/${iVolumeGroup}-${iName}.`date +%Y-%m-%d-%H.%M.%S`.gz; ${lvr} -f ${lv_path}_snap";
	fi;
done;
