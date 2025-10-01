#!/bin/bash

set -e

exec > /var/log/anf-mount.log 2>&1
echo "Starting ANF mount script at $(date) on VM ${vm_index}"

# Install NFS client
echo "Installing NFS client..."
apt-get update -q
apt-get install -y nfs-common

# Set NetApp variables
NETAPP_IP="${volume_ip}"
NETAPP_PATH="/${volume_name}"
MOUNT_PATH="/mnt/${volume_name}"
VM_SPECIFIC_PATH="$MOUNT_PATH/vm-${vm_index}"

echo "NetApp IP: $NETAPP_IP"
echo "NetApp Path: $NETAPP_PATH"
echo "Mount Path: $MOUNT_PATH"
echo "VM Specific Path: $VM_SPECIFIC_PATH"

# Create mount directory
echo "Creating mount directory..."
mkdir -p $MOUNT_PATH
chmod 777 $MOUNT_PATH

# Wait for NetApp endpoint to be reachable
echo "Checking if NetApp endpoint is reachable..."
RETRIES=30
count=0
while [ $count -lt $RETRIES ]; do
    if ping -c 1 $NETAPP_IP &> /dev/null; then
        echo "NetApp endpoint is reachable"
        break
    fi
    
    count=$((count+1))
    echo "Waiting for NetApp endpoint... Attempt $count of $RETRIES"
    sleep 10
done

if [ $count -eq $RETRIES ]; then
    echo "ERROR: Could not reach NetApp endpoint after $RETRIES attempts"
    exit 1
fi

# Mount the volume
echo "Mounting ANF volume..."
mount -t nfs -o rw,hard,rsize=262144,wsize=262144,vers=3,tcp $NETAPP_IP:$NETAPP_PATH $MOUNT_PATH

# Check if mount was successful
if mount | grep -q "$MOUNT_PATH"; then
    echo "Mount successful!"
    
    # Create VM-specific directory
    echo "Creating VM-specific directory..."
    mkdir -p $VM_SPECIFIC_PATH
    chmod 755 $VM_SPECIFIC_PATH
    
    # Add to fstab for persistence
    echo "Adding to fstab for persistence..."
    grep -v "$MOUNT_PATH" /etc/fstab > /etc/fstab.new
    mv /etc/fstab.new /etc/fstab
    echo "$NETAPP_IP:$NETAPP_PATH $MOUNT_PATH nfs rw,hard,rsize=262144,wsize=262144,vers=3,tcp 0 0" >> /etc/fstab
    
    # Create test files
    echo "Creating test files..."
    touch $MOUNT_PATH/shared-mount-successful
    echo "VM ${vm_index} mounted successfully at $(date)" > $VM_SPECIFIC_PATH/mount-info.txt
    
    echo "ANF volume successfully mounted at $MOUNT_PATH"
    echo "VM-specific directory created at $VM_SPECIFIC_PATH"
    exit 0
else
    echo "ERROR: Mount verification failed"
    exit 1
fi

