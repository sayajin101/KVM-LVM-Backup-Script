#!/bin/bash

#--========================================--#
# Set Varibles				#
# Only Change the below varibles you need to #
#--========================================--#
remotePort="22";
remoteUser="root";
remoteAddress="backup.server.ip";
localBackupPath="/backup/path";
#--========================================--#

scriptPath=$(dirname "${BASH_SOURCE[0]}");
configFile="${scriptPath}/kvm-lvm-remote-backup.cfg";
[ ! -f ${configFile} ] && { echo -e "\nConfig file not found, creating it\nPlease add your LVMs to the config file before continuing\n" && touch ${configFile} && exit 1; };
[ ! -s ${configFile} ] && { echo -e "\n${configFile} is empty, please fill in your LVM details\n" && exit 1; };

lvc=$(which lvcreate);
lvr=$(which lvremove);

# Check Folder Structure
[ ! -d "${scriptPath}/key" ] || [ ! -d "${scriptPath}/logs" ] && mkdir -p "${scriptPath}"/{key,logs};

# Check if ssh key exists
[ ! -f "${scriptPath}/key/lvm-backup" ] && { ssh-keygen -b 4096 -q -t rsa -N "" -C "Remote KVM LVM Backups" -f "${scriptPath}/key/lvm-backup" && chmod 644 ${scriptPath}/key/lvm-backup* && echo -e "\nSSH Key has been created in ${scriptPath}/key called lvm-backup.pub\nYou must copy the key to your remote server.\nSSH key copy command: cat ${scriptPath}/key/lvm-backup.pub | ssh user@hostname 'cat >> .ssh/authorized_keys'\n" && exit 1; };

log() {
	if [ "${1}" == "error" ]; then
		echo "[`date +%Y-%m-%d_%H.%M.%S`] ${1} ${2}" >> ${scriptPath}/logs/error.log;
		echo "[`date +%Y-%m-%d_%H.%M.%S`] ${1} ${2}" >> ${scriptPath}/logs/complete.log;
	elif [ "${1}" == "success" ]; then
		echo "[`date +%Y-%m-%d_%H.%M.%S`] ${1} ${2}" >> ${scriptPath}/logs/success.log;
		echo "[`date +%Y-%m-%d_%H.%M.%S`] ${1} ${2}" >> ${scriptPath}/logs/complete.log;
	fi;
}

# Get Hostname
hName=$(hostname);

for backupList in `grep -v '^#' ${configFile} | awk '{print $2}'`; do

# LVM Backup Function
lvmBackup() {
	iName=$(grep "${backupList}" ${configFile} | awk '{print $2}');
	iVolumeGroup=$(grep "${backupList}" ${configFile} | awk '{print $3}');
	iRemotePath=$(grep "${backupList}" ${configFile} | awk '{print $4}');
	iCompressionLocation=$(grep "${backupList}" ${configFile} | awk '{print $5}');
	iRemoteStorgeType=$(grep "${backupList}" ${configFile} | awk '{print $6}');

	# Check for stale snapshot & remove
	[ `lvs --separator ',' | awk -F ',' '$6 == '\"${iName}\"' && $2 == '\"${iVolumeGroup}\"' {print $1}' | tr -d ' ' | wc -l` -ne "0" ] && ${lvr} -f ${iVolumeGroup}\/${iName}_snap;

	lv_path=$(lvscan | grep "`echo ${iVolumeGroup}\/${iName}`" | awk '{print $2}' | tr -d "'");
	[ -z "${lv_path}" ] && { log error "Error: LVM path ${lv_path} does not exist, correct the path name in config file" && continue; };

	[ -z "${iName}" ] && { log error "Error: No LVM Name, Volume Group, Remote Mount or Compression Location Specified...Skipping" && continue; };
	[ -z "${iVolumeGroup}" ] && { log error "Error: No LVM Name, Volume Group, Remote Mount or Compression Location Specified...Skipping" && continue; };
	[ -z "${iRemotePath}" ] && { log error "Error: No LVM Name, Volume Group, Remote Mount or Compression Location Specified...Skipping" && continue; };
	[ -z "${iCompressionLocation}" ] && { log error "Error: No LVM Name, Volume Group, Remote Mount or Compression Location Specified...Skipping" && continue; };
	[ -z "${iRemoteStorgeType}" ] && { log error "Error: No LVM Name, Volume Group, Remote Mount or Compression Location Specified...Skipping" && continue; };

	if [ "${iRemoteStorgeType}" == "mounted" ]; then
		# Check if backup file system is mounted on remote server if not then try to mount the backup volume
		mountCheck=$(ssh -i ${scriptPath}/key/lvm-backup -p ${remotePort} ${remoteUser}@${remoteAddress} "mount | grep -qs '${iRemotePath}' && echo 'mounted' || { mount ${iRemotePath} > /dev/null 2>&1 && [ ${?} -eq 0 ] && echo 'mount successful' || echo 'something went wrong'; }";);

		# Backup volume remote mount check result check
		[ "${mountCheck}" == "something went wrong" ] && { log error "Error: Remote Server backup mount is not mounted & mount attemtp failed...exiting" && continue; };
	fi;

	size=$(lvs ${lv_path} -o LV_SIZE --noheadings --units g --nosuffix | tr -d ' ');

	date=$(date +%Y-%m-%d_%H.%M.%S);

	if [ "${iCompressionLocation}" == "remote" ]; then
		${lvc} -s --size=${size}G -n ${iName}_snap ${lv_path};
		copyBackup() {
			[ -z "${copyCount}" ] && copyCount="1";
			[ "${copyCount}" -gt "3" ] && { log error "Error: Copy failed after 3 attempts for ${hName}.${iVolumeGroup}-${iName} to backup server ${remoteAddress}." && continue; };
			/bin/dd if=${lv_path}_snap bs=16MB | ssh -i ${scriptPath}/key/lvm-backup -p ${remotePort} ${remoteUser}@${remoteAddress} "/bin/gzip -c | /bin/dd of=${iRemotePath}/vms/${hName}.${iVolumeGroup}-${iName}.${date}.gz;";
			gzipIntegrity=$(ssh -i ${scriptPath}/key/lvm-backup -p ${remotePort} ${remoteUser}@${remoteAddress} "gunzip -t ${iRemotePath}/vms/${hName}.${iVolumeGroup}-${iName}.${date}.gz > /dev/null 2>&1; echo $?;";);
			if [ "${gzipIntegrity}" -ne "0" ]; then
				log error "Backup file integrity error...backup file restarting backup procedure";
				(( copyCount++ ));
				copyBackup;
			else
				${lvr} -f ${lv_path}_snap;
				log success "Copy for ${hName}.${iVolumeGroup}-${iName} to backup server ${remoteAddress} was successful.";
			fi;
		};
		copyBackup;
	elif [ "${iCompressionLocation}" == "local" ]; then
		mkdir -p ${localBackupPath};
		${lvc} -s --size=${size}G -n ${iName}_snap ${lv_path};
		copyBackup() {
			[ -z "${copyCount}" ] && copyCount="1";
			[ "${copyCount}" -gt "3" ] && { log error "Error: Copy failed after 3 attempts for ${hName}.${iVolumeGroup}-${iName} to backup server ${remoteAddress}." && continue; };
			/bin/dd if=${lv_path}_snap bs=16MB | /bin/gzip -c | ssh -i ${scriptPath}/key/lvm-backup -p ${remotePort} ${remoteUser}@${remoteAddress} "/bin/dd of=${iRemotePath}/vms/${hName}.${iVolumeGroup}-${iName}.${date}.gz;";
			gzipIntegrity=$(ssh -i ${scriptPath}/key/lvm-backup -p ${remotePort} ${remoteUser}@${remoteAddress} "gunzip -t ${iRemotePath}/vms/${hName}.${iVolumeGroup}-${iName}.${date}.gz > /dev/null 2>&1; echo $?;";);
			if [ "${gzipIntegrity}" -ne "0" ]; then
				log error "Backup file integrity error...backup file restarting backup procedure";
				(( copyCount++ ));
				copyBackup;
			else
				${lvr} -f ${lv_path}_snap;
				log success "Copy for ${hName}.${iVolumeGroup}-${iName} to backup server ${remoteAddress} was successful.";
			fi;
		};
		copyBackup;
	fi;
}

# KVM Backup Function
kvmBackup() {
	iDomName=$(grep "${backupList}" ${configFile} | awk '{print $2}');
	iRemotePath=$(grep "${backupList}" ${configFile} | awk '{print $3}');
	iCompressionLocation=$(grep "${backupList}" ${configFile} | awk '{print $4}');
	iRemoteStorgeType=$(grep "${backupList}" ${configFile} | awk '{print $5}');

	date=$(date +%Y-%m-%d_%H.%M.%S);

	# Dump KVM Domain XML file
	virsh dumpxml ${iDomName} | ssh -i ${scriptPath}/key/lvm-backup -p ${remotePort} ${remoteUser}@${remoteAddress} "cat > ${iRemotePath}/vms/${iDomName}.${date}.xml"

	for lvm in `virsh dumpxml "${iDomName}" | grep 'source dev' | grep -o "'.*'" | tr -d "'" | rev | cut -d '/' -f1 | rev`; do
		iVolumeGroup=$(echo "${lvm}" | awk -F '-' '{print $1}');
		iName=$(echo "${lvm}" | awk -F '-' '{print $2}');

		# Check for stale snapshot & remove
		[ `lvs --separator ',' | awk -F ',' '$6 == '\"${iName}\"' && $2 == '\"${iVolumeGroup}\"' {print $1}' | tr -d ' ' | wc -l` -ne "0" ] && ${lvr} -f ${iVolumeGroup}\/${iName}_snap;

		lv_path=$(lvscan | grep "`echo ${iVolumeGroup}\/${iName}`" | awk '{print $2}' | tr -d "'");
		[ -z "${lv_path}" ] && { log error "Error: LVM path ${lv_path} does not exist, correct the path name in config file" && continue; };

		[ -z "${iName}" ] && { log error "Error: No LVM Name, Volume Group, Remote Mount or Compression Location Specified...Skipping" && continue; };
		[ -z "${iVolumeGroup}" ] && { log error "Error: No LVM Name, Volume Group, Remote Mount or Compression Location Specified...Skipping" && continue; };
		[ -z "${iRemotePath}" ] && { log error "Error: No LVM Name, Volume Group, Remote Mount or Compression Location Specified...Skipping" && continue; };
		[ -z "${iCompressionLocation}" ] && { log error "Error: No LVM Name, Volume Group, Remote Mount or Compression Location Specified...Skipping" && continue; };
		[ -z "${iRemoteStorgeType}" ] && { log error "Error: No LVM Name, Volume Group, Remote Mount or Compression Location Specified...Skipping" && continue; };

		if [ "${iRemoteStorgeType}" == "mounted" ]; then
			# Check if backup file system is mounted on remote server if not then try to mount the backup volume
			mountCheck=$(ssh -i ${scriptPath}/key/lvm-backup -p ${remotePort} ${remoteUser}@${remoteAddress} "mount | grep -qs '${iRemotePath}' && echo 'mounted' || { mount ${iRemotePath} > /dev/null 2>&1 && [ ${?} -eq 0 ] && echo 'mount successful' || echo 'something went wrong'; }";);

			# Backup volume remote mount check result check
			[ "${mountCheck}" == "something went wrong" ] && { log error "Error: Remote Server backup mount is not mounted & mount attemtp failed...exiting" && continue; };
		fi;

		size=$(lvs ${lv_path} -o LV_SIZE --noheadings --units g --nosuffix | tr -d ' ');


		if [ "${iCompressionLocation}" == "remote" ]; then
			${lvc} -s --size=${size}G -n ${iName}_snap ${lv_path};
			copyBackup() {
				[ -z "${copyCount}" ] && copyCount="1";
				[ "${copyCount}" -gt "3" ] && { log error "Error: Copy failed after 3 attempts for ${hName}.${iVolumeGroup}-${iName} to backup server ${remoteAddress}." && continue; };
				/bin/dd if=${lv_path}_snap bs=16MB | ssh -i ${scriptPath}/key/lvm-backup -p ${remotePort} ${remoteUser}@${remoteAddress} "/bin/gzip -c | /bin/dd of=${iRemotePath}/vms/${hName}.${iVolumeGroup}-${iName}.${date}.gz;";
				gzipIntegrity=$(ssh -i ${scriptPath}/key/lvm-backup -p ${remotePort} ${remoteUser}@${remoteAddress} "gunzip -t ${iRemotePath}/vms/${hName}.${iVolumeGroup}-${iName}.${date}.gz > /dev/null 2>&1; echo $?;";);
				if [ "${gzipIntegrity}" -ne "0" ]; then
					log error "Backup file integrity error...backup file restarting backup procedure";
					(( copyCount++ ));
					copyBackup;
				else
					${lvr} -f ${lv_path}_snap;
					log success "Copy for ${hName}.${iVolumeGroup}-${iName} to backup server ${remoteAddress} was successful.";
				fi;
			};
			copyBackup;
		elif [ "${iCompressionLocation}" == "local" ]; then
			mkdir -p ${localBackupPath};
			${lvc} -s --size=${size}G -n ${iName}_snap ${lv_path};
			copyBackup() {
				[ -z "${copyCount}" ] && copyCount="1";
				[ "${copyCount}" -gt "3" ] && { log error "Error: Copy failed after 3 attempts for ${hName}.${iVolumeGroup}-${iName} to backup server ${remoteAddress}." && continue; };
				/bin/dd if=${lv_path}_snap bs=16MB | /bin/gzip -c | ssh -i ${scriptPath}/key/lvm-backup -p ${remotePort} ${remoteUser}@${remoteAddress} "/bin/dd of=${iRemotePath}/vms/${hName}.${iVolumeGroup}-${iName}.${date}.gz;";
				gzipIntegrity=$(ssh -i ${scriptPath}/key/lvm-backup -p ${remotePort} ${remoteUser}@${remoteAddress} "gunzip -t ${iRemotePath}/vms/${hName}.${iVolumeGroup}-${iName}.${date}.gz > /dev/null 2>&1; echo $?;";);
				if [ "${gzipIntegrity}" -ne "0" ]; then
					log error "Backup file integrity error...backup file restarting backup procedure";
					(( copyCount++ ));
					copyBackup;
				else
					${lvr} -f ${lv_path}_snap;
					log success "Copy for ${hName}.${iVolumeGroup}-${iName} to backup server ${remoteAddress} was successful.";
				fi;
			};
			copyBackup;
		fi;
	done;

	}

if [ `grep "${backupList}" ${configFile} | awk '{print $1}'` == "kvm" ]; then
	kvmBackup;
elif [ `grep "${backupList}" ${configFile} | awk '{print $1}'` == "lvm" ]; then
	lvmBackup;
fi;

done;
