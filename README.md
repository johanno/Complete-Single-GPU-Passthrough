TODO:::: Much better Tutorial and easier to install:
https://github.com/ilayna/Single-GPU-passthrough-amd-nvidia


## **Table Of Contents**

* **[IOMMU Setup](#enable--verify-iommu)**
* **[Installing Packages](#install-required-tools)**
* **[Enabling Services](#enable-required-services)**
* **[Guest Setup](#setup-guest-os)**
* **[Attching PCI Devices](#attaching-pci-devices)**
* **[Libvirt Hooks](#libvirt-hooks)**
* **[Keyboard/Mouse Passthrough](#keyboardmouse-passthrough)**
* **[Video Card Virtualisation Detection](#video-card-driver-virtualisation-detection)**
* **[Audio Passthrough](#audio-passthrough)**
* **[GPU vBIOS Patching](#vbios-patching)**

### **Enable & Verify IOMMU**

***BIOS Settings*** \
Enable ***Intel VT-d*** or ***AMD-Vi*** in BIOS settings. \
If you can't find those virtualization options in BIOS, your hardware probably doesn't support it.

***Set the kernel paramater depending on your CPU.*** \
For GRUB user, edit grub configuration.

| /etc/default/grub |
| ----- |
| `GRUB_CMDLINE_LINUX_DEFAULT="... intel_iommu=on iommu=pt ..."` |
| OR |
| `GRUB_CMDLINE_LINUX_DEFAULT="... amd_iommu=on iommu=pt ..."` |

---
***Generate grub.cfg***

### Debian/Arch:

 ```sh
 sudo update-grub
 ```

### Fedora:

for UEFI systems:

 ```sh
 sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg 
 ```

for BIOS systems //TODO afaik without uefi it doesn't work anyways

 ```sh
 sudo grub2-mkconfig -o /boot/grub2/grub.cfg
 ```

<br/>
Reboot your system for the changes to take effect.

---

***To verify IOMMU, run the following command, which should show devices.***

```sh
sudo dmesg | grep 'IOMMU enabled'
```

or 
after a restart you can verify it with the following commands:

for Intel:

```sh
dmesg | grep "Virtualization Technology"
```

for AMD:

```sh
dmesg | grep AMD-Vi
```

Now, you need to make sure that your IOMMU groups are valid. \
Run the following script to view the IOMMU groups and attached devices. 

```sh
#!/bin/bash
shopt -s nullglob
for g in `find /sys/kernel/iommu_groups/* -maxdepth 0 -type d | sort -V`; do
    echo "IOMMU Group ${g##*/}:"
    for d in $g/devices/*; do
        echo -e "\t$(lspci -nns ${d##*/})"
    done;
done;
```

Example output:

```sh
IOMMU Group 23:
        04:00.0 Network controller [0280]: Qualcomm Atheros AR9287 Wireless Network Adapter (PCI-Express) [168c:002e] (rev 01)
IOMMU Group 24:
        05:00.0 Ethernet controller [0200]: Intel Corporation I211 Gigabit Network Connection [8086:1539] (rev 03)
IOMMU Group 25:
        09:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU106 [GeForce RTX 2070] [10de:1f02] (rev a1)
        09:00.1 Audio device [0403]: NVIDIA Corporation TU106 High Definition Audio Controller [10de:10f9] (rev a1)
        09:00.2 USB controller [0c03]: NVIDIA Corporation TU106 USB 3.1 Host Controller [10de:1ada] (rev a1)
        09:00.3 Serial bus controller [0c80]: NVIDIA Corporation TU106 USB Type-C UCSI Controller [10de:1adb] (rev a1)
IOMMU Group 26:
        0a:00.0 Non-Essential Instrumentation [1300]: Advanced Micro Devices, Inc. [AMD] Starship/Matisse PCIe Dummy Function [1022:148a]
IOMMU Group 27:
```

During passthrough, you need to pass every device (except PCI) in the group which includes your GPU. \
You can avoid having to pass everything by
using [ACS override patch](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#Bypassing_the_IOMMU_groups_(ACS_override_patch))
.

### **TODO VFIO**

debian:
/etc/modprobe.d/vfio.conf

 ```sh
 options vfio-pci ids=10de:1f02,10de:10f9
```

ids here are the ids we can see in the IOMMU Group of our graphics card

Hat man den Grafiktreiber nicht geblacklistet, oder hat mehr als 1 Nvidia bzw. AMD Grafikkarte muss am besten noch
folgendes in die Datei /etc/modprobe.d/vfio.conf hinzugefügt werden:

für Nvidia:

```sh
softdep nouveau pre: vfio-pci
```

für AMD:notwenig

```sh
softdep amdgpu pre: vfio-pci
```

bzw. für alte AMD Karten:

```sh
softdep radeon pre: vfio-pci
```

example file:

```sh
options vfio-pci ids=10de:1f02,10de:10f9
softdep nouveau pre: vfio-pci
```

Then:

```sh
sudo gedit /etc/modules
```

```sh
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
```

arch:

<https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#Loading_vfio-pci_early>

### **Install required tools**

<details>
  <summary><b>Gentoo Linux</b></summary>
  RECOMMENDED USE FLAGS: app-emulation/virt-manager gtk<br>
&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp;&emsp; app-emulation/qemu spice usb usbredir pulseaudio

  ```sh
  sudo emerge -av qemu virt-manager libvirt ebtables dnsmasq
  ```

</details>

<details>
  <summary><b>Arch Linux</b></summary>

  ```sh
  sudo pacman -S qemu libvirt edk2-ovmf virt-manager dnsmasq ebtables
  ```

</details>

<details>
  <summary><b>Fedora</b></summary>

  ```sh
  sudo dnf install @virtualization
  ```

</details>

<details>
  <summary><b>Ubuntu</b></summary>

  ```sh
  sudo apt install qemu-kvm qemu-utils libvirt-daemon-system libvirt-clients bridge-utils virt-manager ovmf
  ```

</details>

### **Enable required services**

<details>
  <summary><b>SystemD</b></summary>

  ```sh
  sudo systemctl enable --now libvirtd
  ```

</details>

<details>
  <summary><b>OpenRC</b></summary>

  ```sh
  sudo rc-update add libvirtd default
  sudo rc-service libvirtd start
  ```

</details>

**OPTIONAL**
Sometimes, you might need to start default network manually.

```sh
virsh net-start default
virsh net-autostart default
```

### **Setup Guest OS**

***NOTE: You should replace win10 with your VM's name where applicable*** \
You should add your user to ***libvirt*** group to be able to run VM without root. And, ***input*** and ***kvm*** group
for passing input devices.

```sh
sudo usermod -aG kvm,input,libvirt $USER
```

<!-- (TODO: add images and stuff?) -->

Download [virtio](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso)
driver. \
[https://github.com/virtio-win/virtio-win-pkg-scripts/](https://github.com/virtio-win/virtio-win-pkg-scripts/). \
Launch ***virt-manager*** and create a new virtual machine. Select ***Customize before install*** on Final Step. \
In ***Overview*** section, set ***Chipset*** to ***Q35***, and ***Firmware*** to ***UEFI*** \
In ***CPUs*** section, set ***CPU model*** to ***host-passthrough***, and ***CPU Topology*** to whatever fits your
system. \
For ***SATA*** disk of VM, set ***Disk Bus*** to ***virtio***. \
In ***NIC*** section, set ***Device Model*** to ***virtio***  
Add Hardware > CDROM: virtio-win.iso \
Now, ***Begin Installation***. Windows can't detect the ***virtio disk***, so you need to ***Load Driver*** and
select ***virtio-iso/amd64/win10*** when prompted. \
After successful installation of Windows, install virtio drivers from virtio CDROM. You can then remove virtio iso.

If you don't have a working internet connection:
- Go to device manager and uninstall drivers and delete them.
- Restart and click on update drivers
- select install local drivers and go to the virtio cdrom and select NetKVM then the os and your hardware

### **Attaching PCI devices**

//TODO do not remove everything... other tutorial recommends spice and video for sound

Remove Channel Spice, Display Spice, Video QXL, Sound ich* and other unnecessary devices. \
Now, click on ***Add Hardware***, select ***PCI Devices*** and add the PCI Host devices for your GPU's VGA and HDMI
Audio. Don't forget to add everything even the USB pcis

//TODO rewrite
// NOTE!!! do not try to test out the changes (dumb me) you have to finish the "Video card driver virtualisation
detection" section later down first.
// Also if your hardware config changes (added pci wifi card for example) then you need to redo this step since the pci
adresses change.

### **Libvirt Hooks**

Libvirt hooks automate the process of running specific tasks during VM state change. \
More info at: [PassthroughPost](https://passthroughpo.st/simple-per-vm-libvirt-hooks-with-the-vfio-tools-hook-helper/)

**Note**: Comment Unbind/rebind EFI framebuffer line from start and stop script if you're using AMD 6000 series cards,
thanks to [cdgriffith](https://github.com/cdgriffith).
Also, move the line to unload AMD kernal module below detaching devices from host. These might also apply to older AMD
cards.

//TODO run this for a quick install of the following libvirt hook install

```sh
mkdir libvirt_hook_install
cd libvirt_hook_install
curl -O https://raw.githubusercontent.com/johanno/Complete-Single-GPU-Passthrough/master/install_libvirt_hooks.bash
chmod +x install_libvirt_hooks.bash
# pcie ids in Hex? Dec? TODO 
./install_libvirt_hooks.bash gpu-type(nvidia|amd) virt-machine-name pci-id1 pci-id2 pci-id3 ...
# Example:                                  nvidia gpu and audio ids
./install_libvirt_hooks.bash nvidia win10 04:00.0 04:00.1
```

<details>
  <summary><b>Create Libvirt Hook</b></summary>

  ```sh
  mkdir /etc/libvirt/hooks
  touch /etc/libvirt/hooks/qemu
  chmod +x /etc/libvirt/hooks/qemu
  ```

  <table>
  <tr>
  <th>
    /etc/libvirt/hooks/qemu
  </th>
  </tr>

  <tr>
  <td>

  ```sh
  #!/bin/bash

GUEST_NAME="$1"
HOOK_NAME="$2"
STATE_NAME="$3"
MISC="${@:4}"

BASEDIR="$(dirname $0)"

HOOKPATH="$BASEDIR/qemu.d/$GUEST_NAME/$HOOK_NAME/$STATE_NAME"
set -e # If a script exits with an error, we should as well.

if [ -f "$HOOKPATH" ]; then
  eval \""$HOOKPATH"\" "$@"
elif [ -d "$HOOKPATH" ]; then
  while read file; do
    eval \""$file"\" "$@"
  done <<< "$(find -L "$HOOKPATH" -maxdepth 1 -type f -executable -print;)"
fi
  ```

  </td>
  </tr>
  </table>
</details>

<details>
  <summary><b>Create Start Script</b></summary>

  ```sh
  mkdir -p /etc/libvirt/hooks/qemu.d/win10/prepare/begin
  touch /etc/libvirt/hooks/qemu.d/win10/prepare/begin/start.sh
  chmod +x /etc/libvirt/hooks/qemu.d/win10/prepare/begin/start.sh
  ```

  <table>
  <tr>
  <th>
    /etc/libvirt/hooks/qemu.d/win10/prepare/begin/start.sh
  </th>
  </tr>

  <tr>
  <td>

  ```sh
#!/bin/bash
set -x

# Stop display manager
systemctl stop display-manager
# rc-service xdm stop
      
# Unbind VTconsoles: might not be needed
echo 0 > /sys/class/vtconsole/vtcon0/bind
echo 0 > /sys/class/vtconsole/vtcon1/bind

# Unbind EFI Framebuffer
echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind

# Unload NVIDIA kernel modules
modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia

# Unload AMD kernel module
# modprobe -r amdgpu

# Detach GPU devices from host
# Use your GPU and HDMI Audio PCI host device
virsh nodedev-detach pci_0000_01_00_0
virsh nodedev-detach pci_0000_01_00_1

# Load vfio module
modprobe vfio-pci
  ```

  </td>
  </tr>
  </table>
</details>

<details>
  <summary><b>Create Stop Script</b></summary>

  ```sh
  mkdir -p /etc/libvirt/hooks/qemu.d/win10/release/end
  touch /etc/libvirt/hooks/qemu.d/win10/release/end/stop.sh
  chmod +x /etc/libvirt/hooks/qemu.d/win10/release/end/stop.sh
  ```

  <table>
  <tr>
  <th>
    /etc/libvirt/hooks/qemu.d/win10/release/end/stop.sh
  </th>
  </tr>

  <tr>
  <td>

  ```sh
#!/bin/bash
set -x

# Unload vfio module
modprobe -r vfio-pci

# Attach GPU devices to host
# Use your GPU and HDMI Audio PCI host device
virsh nodedev-reattach pci_0000_01_00_0
virsh nodedev-reattach pci_0000_01_00_1

# Rebind framebuffer to host
echo "efi-framebuffer.0" > /sys/bus/platform/drivers/efi-framebuffer/bind

# Load NVIDIA kernel modules
modprobe nvidia_drm
modprobe nvidia_modeset
modprobe nvidia_uvm
modprobe nvidia

# Load AMD kernel module
# modprobe amdgpu
      
# Bind VTconsoles: might not be needed
echo 1 > /sys/class/vtconsole/vtcon0/bind
echo 1 > /sys/class/vtconsole/vtcon1/bind

# Restart Display Manager
systemctl start display-manager
# rc-service xdm start
  ```

  </td>
  </tr>
  </table>
</details>

<!-- TODO: did not work for me: look for easy way to use usb ports !!! -->

### **Keyboard/Mouse Passthrough**

In order to be able to use keyboard/mouse in the VM, you can either passthrough the USB Host device or use Evdev
passthrough.

Using USB Host Device is simple, \
***Add Hardware*** > ***USB Host Device***, add your keyboard and mouse device.

For Evdev passthrough, follow these steps: \
Modify libvirt configuration of your VM. \
**Note**: Save only after adding keyboard and mouse devices or the changes gets lost. \
Using

```sh
sudo virsh edit win10
```

change the first line to:

<table>
<tr>
<th>
virsh edit win10
</th>
</tr>

<tr>
<td>

```xml

<domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
```

</td>
</tr>
</table>

Find your keyboard and mouse devices in ***/dev/input/by-id***. You'd generally use the devices ending with ***
event-kbd*** and ***event-mouse***. And the devices in your configuration right before closing ***`</domain>`*** tag. \
Replace ***MOUSE_NAME*** and ***KEYBOARD_NAME*** with your device id.

<table>
<tr>
<th>
virsh edit win10
</th>
</tr>

<tr>
<td>

```xml
...
<qemu:commandline>
    <qemu:arg value='-object'/>
    <qemu:arg value='input-linux,id=mouse1,evdev=/dev/input/by-id/MOUSE_NAME'/>
    <qemu:arg value='-object'/>
    <qemu:arg value='input-linux,id=kbd1,evdev=/dev/input/by-id/KEYBOARD_NAME,grab_all=on,repeat=on'/>
</qemu:commandline>
        </domain>
```

</td>
</tr>
</table>

You need to include these devices in your qemu config.
<table>
<tr>
<th>
/etc/libvirt/qemu.conf
</th>
</tr>

<tr>
<td>

```sh
...
user = "YOUR_USERNAME"
group = "kvm"
...
cgroup_device_acl = [
    "/dev/input/by-id/KEYBOARD_NAME",
    "/dev/input/by-id/MOUSE_NAME",
    "/dev/null", "/dev/full", "/dev/zero",
    "/dev/random", "/dev/urandom",
    "/dev/ptmx", "/dev/kvm", "/dev/kqemu",
    "/dev/rtc","/dev/hpet", "/dev/sev"
]
...
```

</td>
</tr>
</table>

Also, switch from PS/2 devices to virtio devices. Add the devices inside ***`<devices>`*** block
<table>
<tr>
<th>
virsh edit win10
</th>
</tr>

<tr>
<td>

```xml
...
<devices>
    ...
    <input type='mouse' bus='virtio'/>
    <input type='keyboard' bus='virtio'/>
    ...
</devices>
        ...
```

</td>
</tr>
</table>

### **Audio Passthrough**

VM's audio can be routed to the host. You need ***Pulseaudio***. It's hit or miss. \
You can also
use [Scream](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF#Passing_VM_audio_to_host_via_Scream) instead
of Pulseaudio. \
Modify the libvirt configuration of your VM.
[More detailed tutorial for Pulseaudio](https://mathiashueber.com/virtual-machine-audio-setup-get-pulse-audio-working)
[Failed to initialize PA contextaudio](https://www.reddit.com/r/linux_gaming/comments/5tidzc/a_solution_for_pulseaudio_pa_context_connect/)

<table>
<tr>
<th>
virsh edit win10
</th>
</tr>

<tr>
<td>

```xml
...
        </devices>
<qemu:commandline>
    ...
    <qemu:arg value="-device"/>
    <qemu:arg value="ich9-intel-hda,bus=pcie.0,addr=0x1b"/>
    <qemu:arg value="-device"/>
    <qemu:arg value="hda-micro,audiodev=hda"/>
    <qemu:arg value="-audiodev"/>
    <qemu:arg value="pa,id=hda,server=/run/user/1000/pulse/native"/>
</qemu:commandline>
        </domain>
```

</td>
</tr>
</table>

### **Video card driver virtualisation detection**

Video Card drivers refuse to run in Virtual Machine, so you need to spoof Hyper-V Vendor ID.

```sh
lspci -nn | grep NVIDIA
0a:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU106 [GeForce RTX 2070] [10de:1f03] (rev a1)
```

`[10de:1f03]` the first value is the Vendor ID and the second one the Device ID.

<table>
<tr>
<th>
virsh edit win10
</th>
</tr>

<tr>
<td>

```xml
...
<features>
    ...
    <hyperv>
        ...
        <vendor_id state='on' value='10de'/>
        ...
    </hyperv>
    ...
</features>
        ...
```

</td>
</tr>
</table>

NVIDIA guest drivers also require hiding the KVM CPU leaf:
<table>
<tr>
<th>
virsh edit win10
</th>
</tr>

<tr>
<td>

```xml
...
<features>
    ...
    <kvm>
        <hidden state='on'/>
    </kvm>
    ...
</features>
        ...
```

</td>
</tr>
</table>

### **vBIOS Patching**

***NOTE: You only need patch the dumped ROM file. You don't need to make changes on the hardware BIOS.*** \
While most of the GPU can be passed with stock vBIOS, some GPU requires vBIOS patching depending on your host distro. \
In order to patch vBIOS, you need to first dump the GPU vBIOS from your system. \
If you have Windows installed, you can use [GPU-Z](https://www.techpowerup.com/gpuz) to dump vBIOS. \
To dump vBIOS on Linux, you can use following command (replace PCI id with yours): \
If it doesn't work on your distro, you can try using live cd.

```sh
sudo bash
echo 1 > /sys/bus/pci/devices/0000:01:00.0/rom
cat /sys/bus/pci/devices/0000:01:00.0/rom > path/to/dump/vbios.rom
echo 0 > /sys/bus/pci/devices/0000:01:00.0/rom
```

To patch vBIOS, you need to use Hex Editor (eg., [Okteta](https://utils.kde.org/projects/okteta))

```sh
sudo apt install okteta
```

and trim unnecessary header. \
For NVIDIA GPU, using hex editor, search string “VIDEO”, and remove everything before HEX value 55. //TODO 55 is U in
ascii probably 56 is meant\
This is probably the same for AMD device.

To use patched vBIOS, edit VM's configuration to include patched vBIOS inside ***hostdev*** block of VGA

  <table>
  <tr>
  <th>
  virsh edit win10
  </th>
  </tr>

  <tr>
  <td>

  ```xml
  ...
<hostdev mode='subsystem' type='pci' managed='yes'>
    <source>
        ...
    </source>
    <rom file='/home/me/patched.rom'/>
    ...
</hostdev>
        ...
  ```

  </td>
  </tr>
  </table>

### **See Also**

> [Single GPU Passthrough Troubleshooting](https://docs.google.com/document/d/17Wh9_5HPqAx8HHk-p2bGlR0E-65TplkG18jvM98I7V8)<br/>
> [Single GPU Passthrough by joeknock90](https://github.com/joeknock90/Single-GPU-Passthrough)<br/>
> [Single GPU Passthrough by YuriAlek](https://gitlab.com/YuriAlek/vfio)<br/>
> [Single GPU Passthrough by wabulu](https://github.com/wabulu/Single-GPU-passthrough-amd-nvidia)<br/>
> [ArchLinux PCI Passthrough](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF)<br/>
> [Gentoo GPU Passthrough](https://wiki.gentoo.org/wiki/GPU_passthrough_with_libvirt_qemu_kvm)<br/>
