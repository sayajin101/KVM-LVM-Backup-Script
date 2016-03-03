# KVM-LVM-Backup-Script
Backup Script for KVM's run on LVM's

* This script is designed to do Live LVM Snapshot backups of KVM Virtual Machines
* Once it has created the LVM snapshot it will dd the LVM image & gzip it at the same time to a specified location.
* Once the gzip process is complete it will remove the LVM snapshot.
* This script required a "kvm-lvm-backup.cfg" file to exist which must contain the LVM-Name VolumeGroup
