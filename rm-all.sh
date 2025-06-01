#!/bin/bash
for id in $(podman ps|grep backup_|cut -f 1 -d " ")
do
	podman stop -f $id
	podman rm -f $id
done
for id in $(podman image list|grep backup|tr -s " " " " |cut -f 3 -d " ")
do
	podman rmi -f $id
done
