#!/bin/bash

if [[ $1 == "nvidia" ]] || [[ $1 == "amd" ]]
then
    echo "using $1 gpu"
    echo "#############################"
else
    echo "$1 is not possible as parameter [nvidia|amd]"
    exit -1
fi


curl -O https://raw.githubusercontent.com/johanno/Complete-Single-GPU-Passthrough/master/etc_libvirt_hooks_qemu
curl -O https://raw.githubusercontent.com/johanno/Complete-Single-GPU-Passthrough/master/etc_libvirt_hooks_start.sh
curl -O https://raw.githubusercontent.com/johanno/Complete-Single-GPU-Passthrough/master/etc_libvirt_hooks_stop.sh

if [[ $1 == "amd" ]]
then
    sed -i 's/modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia/modprobe -r amdgpu/' etc_libvirt_hooks_start.sh
fi
if [[ $1 == "nvidia" ]]
then
    sed -i "s/modprobe amdgpu/modprobe nvidia_drm\nmodprobe nvidia_modeset\nmodprobe nvidia_uvm\nmodprobe nvidia/" etc_libvirt_hooks_stop.sh
fi

frontID="0"
middleID="0"
lastID="0"
str=""
str2=""
for var in "$@"
do
    if [[ $var == $0 ]] || [[ $var == $1 ]]
    then 
        continue
    fi
    arrF=(${var//:/ })
    frontID=${arrF[0]}
    arrB=(${arrF[1]//./ })
    middleID=${arrB[0]}
    lastID=${arrB[1]}
    str="${str}virsh nodedev-detach pci_0000_${frontID}_${middleID}_${lastID}\n"
    str2="${str2}virsh nodedev-reattach pci_0000_${frontID}_${middleID}_${lastID}\n"
done
sed -i "s/virsh nodedev-detach pci_0000_01_00_0/$str/" etc_libvirt_hooks_start.sh
sed -i "s/virsh nodedev-reattach pci_0000_01_00_0/$str2/" etc_libvirt_hooks_stop.sh


# sudo mkdir /etc/libvirt/hooks
# sudo mv ..
# sudo chmod +x /etc/libvirt/hooks/qemu

# sudo mkdir -p /etc/libvirt/hooks/qemu.d/win10/prepare/begin
# sudo mv ..
# sudo chmod +x /etc/libvirt/hooks/qemu.d/win10/prepare/begin/start.sh

# sudo mkdir libvirt_hook_install
# sudo mv ..
# sudo chmod +x /etc/libvirt/hooks/qemu.d/win10/prepare/begin/start.sh
