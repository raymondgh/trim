#!/bin/bash

# Check if script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root (sudo). Please rerun the script with sudo."
    exit 1
fi

# Check for sg3-utils and install if not present
check_sg3_utils_and_install() {
    if ! command -v sg_vpd &> /dev/null; then
        echo "sg3-utils is not installed. Installing sg3-utils..."
        apt-get update && apt-get install sg3-utils -y
    fi
}

echo "Hello, let's get TRIM set up for your SSD"
echo "This script will target the SSD connected via the Homerun USB-SATA Adapter"

check_sg3_utils_and_install

# Check if TRIM is already enabled
if sudo fstrim -v / 2>&1 | grep -q 'trimmed'; then
    echo "TRIM is already enabled."
    exit 0
else
    echo "TRIM is not currently enabled on the mounted filesystem."
    echo "Checking if SSD can support TRIM"
fi

# Check TRIM compatibility
check_trim_support() {
    local device=$1
    local unmap_lba_count=$(sg_vpd -p bl "/dev/$device" | grep 'Maximum unmap LBA count' | awk '{print $NF}')
    local lbpu=$(sg_vpd -p lbpv "/dev/$device" | grep 'LBPU' | awk '{print $NF}')

    if [[ "$unmap_lba_count" -gt 0 && "$lbpu" -eq 1 ]]; then
        read -p "TRIM is likely supported with this drive. Enable now? (yes/no): " user_confirmation
        if [[ "$user_confirmation" != "yes" ]]; then
            echo "Did not enable TRIM."
            exit 1
        fi
    else
        echo "unmap lba count is $unmap_lba_count and lbpu is $lbpu"
        echo "TRIM is not supported on your SSD."
        exit 0
    fi
}

# Identify and validate the device
device_path=$(lsusb -vd 5011:0001 2>/dev/null | grep -oP 'iSerial\s+\d\s+\K\S+')
if [ -z "$device_path" ]; then
    echo "Error: Unable to identify the USB-SATA device. Please ensure it is connected and try again."
    exit 1
fi
device=$(ls -l /dev/disk/by-id/ | grep "$device_path" | awk '{print $NF}' | grep -m 1 -o 'sd[a-z]')
if [ -z "$device" ]; then
    echo "Error: Unable to find the device in /dev/disk/by-id/. Please ensure the device is correctly connected."
    exit 1
fi

check_trim_support "$device"



max_unmap_lba_count=$(sg_vpd -p bl "/dev/$device" | grep 'Maximum unmap LBA count' | awk '{print $NF}')
logical_block_length=$(sg_readcap -l "/dev/$device" | grep 'Logical block length' | awk '{print $NF}')
echo "(1/4) Setting max discard bytes"
discard_max_bytes=$((max_unmap_lba_count * logical_block_length))
echo $discard_max_bytes > /sys/block/${device##*/}/queue/discard_max_bytes

# Step 1: Store results from find
provisioning_mode_paths=($(find /sys/ -name provisioning_mode -exec grep -H . {} + | sort))

# Step 2: Find bus and device number
usb_device=$(lsusb | grep "5011:0001")
bus=$(echo "$usb_device" | awk '{print $2}')
device_number=$(echo "$usb_device" | awk '{print $4}' | sed 's/://')

# Step 3: Use udevadm to find more information
sysfs_substring=$(udevadm info --query=path --name=/dev/bus/usb/"$bus"/"$device_number")

# Step 4: Set the provisioning mode path based on substring match
provisioning_mode_path=""
for path in "${provisioning_mode_paths[@]}"; do
    if [[ "$path" == *"$sysfs_substring"* ]]; then
        provisioning_mode_path="${path%:*}"
        break
    fi
done

if [ -z "$provisioning_mode_path" ]; then
    echo "Error: Provisioning mode path not found."
    exit 1
fi

# [Commands to set provisioning mode and apply changes]

echo "(2/4) Setting provisioning mode to unmap"
echo unmap > "$provisioning_mode_path"
echo "(3/4) Creating udev rule"
udev_rule_path="/etc/udev/rules.d/10-trim.rules"
echo 'ACTION=="add|change", ATTRS{idVendor}=="5011", ATTRS{idProduct}=="0001", SUBSYSTEM=="scsi_disk", ATTR{provisioning_mode}="unmap"' > "$udev_rule_path"
echo "(4/4) Scheduling TRIM to run weekly"
sudo systemctl enable fstrim.timer

echo "TRIM is now enabled and configured to persist. Enjoy!"
