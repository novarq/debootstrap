# Building and Deploying Ubuntu/Debian on Novarq Tactical 1000

Run Ubuntu or Debian directly on your Tactical 1000 switch. Build custom distribution with full apt repositories, and leverage the switch's hardware acceleration through standard Linux interfaces. This guide provides the essential workflow, from debootstrap through kernel compilation to deployment.

## Why Custom Distributions Matter

Your network infrastructure deserves an operating system that works for you, not against you. While the Tactical 1000 ships with Buildroot for immediate functionality, custom distributions unlock the full potential of Linux-native networking:

- **Complete Package Ecosystem**: Access to thousands of packages through apt repositories
- **Familiar Development Environment**: Standard Ubuntu/Debian tools and workflows
- **Advanced Networking Capabilities**: Full Linux networking stack with modern features
- **Operational Flexibility**: Deploy the exact software stack your environment requires

## Prerequisites

### Development Environment
- Any Linux host system (adapt package manager commands to your distribution)
- Root access for mounting and chroot operations
- Internet connectivity for package downloads
- Minimum 4GB free disk space

### Required Packages
```bash
# Install essential build dependencies
sudo apt update
sudo apt install -y debootstrap qemu-user-static coreutils tar xz-utils
```

### Hardware Requirements
- Novarq Tactical 1000 switch
- USB storage device (8GB+ recommended)
- Serial console access (see [Serial Console Guide](serial-console-access.md))
- Network connectivity for the switch

## Building Your Custom Distribution

### Step 1: Obtain the Novarq Instant rootfs Script

This script creates a complete Ubuntu or Debian root filesystem optimized for the Tactical 1000's ARM64 architecture.

```bash
# Download the Novarq instant rootfs script
wget https://raw.githubusercontent.com/novarq/debootstrap/refs/heads/main/novarq-instant-rootfs.sh
chmod +x novarq-instant-rootfs.sh
```

### Step 2: Build the Root Filesystem

The script supports Ubuntu Noble (24.04 LTS) and Debian Bookworm (12) targets. Build your distribution using the Novarq instant rootfs script:

#### For Ubuntu Noble
```bash
sudo ./novarq-instant-rootfs.sh tactical1000 noble
# example with added packages
# sudo ./novarq-instant-rootfs.sh tactical1000 noble curl vim git
```

#### For Debian Bookworm
```bash
sudo ./novarq-instant-rootfs.sh tactical1000 bookworm
# example with added packages
# sudo ./novarq-instant-rootfs.sh tactical1000 bookworm curl vim git
```

**What This Creates:**
- Complete ARM64 root filesystem in `tactical1000-[distro]/` directory
- Compressed tarball: `tactical1000-[distro].tar.xz`
- Package manifests for tracking installed software
- Optimized configuration for switch hardware

The build process typically takes 15-30 minutes depending on your internet connection and system performance.

### Step 3: Build Kernel via Buildroot

Your custom distribution requires a compatible kernel optimized for the Tactical 1000's hardware architecture. Follow the comprehensive build procedures at [Buildroot External Novarq](https://github.com/novarq/buildroot-external-novarq).

The build process creates a hardware-specific kernel that bridges your custom Ubuntu or Debian distribution with the switch's enterprise-grade networking capabilities. This kernel provides the essential foundation that transforms your Linux distribution of choice into high-performance networking platform.

### Step 4: Build Initramfs-enabled Buildroot image

**Important:** Save the uImage-lan969x.itb file built in Step 3 to USB or a safe location before proceeding, as Buildroot will overwrite it with a new image of the same name that includes initramfs.

This step is required as we will leverage this initramfs-enabled image to flash the images from Step 2 & 3 onto Tactical 1000.

Now proceed to build the initramfs-enabled kernel by following [Buildroot External Novarq](https://github.com/novarq/buildroot-external-novarq) build procedure with the following change to enable initramfs support:

```bash
# Enter into buildroot source directory
cd buildroot
make BR2_EXTERNAL=../buildroot-external-novarq/ novarq_tactical_1000_defconfig

# MUST enable initramfs support for deployment flexibility
make menuconfig
# Navigate to: Filesystem images -> Initial RAM filesystem linked into linux kernel
# Enable this option, save configuration and exit

# Clean previously built artifacts (save kernel image to another location if not already done)
make linux-dirclean

# Rebuild
make
# This generates the essential image: output/images/uImage-lan969x.itb

rename output/images/uImage-lan969x.itb into uImage-lan969x_initramfs.itb
```

### Step 5: Prepare to Deploy Images

Copy your `tactical1000-[distro].tar.xz` archive (built in Step 2), `uImage-lan969x.itb` kernel image (built in Step 3) and  `uImage-lan969x_initramfs.itb` (built in Step 4) to USB storage.

Connect via serial console following the [Serial Console Guide](https://github.com/novarq/tactical-1000/blob/main/docs/serial-console-access.md).

Access the U-Boot prompt during boot process through your serial console connection (interrupt boot sequence) to boot from the initramfs image.

```bash
# Start USB
usb start

# Load the kernel image (adjust path if needed)
ext4load usb 0:1 ${loadaddr} /uImage-lan969x_initramfs.itb

# Boot the kernel image
bootm ${loadaddr}
```

The system will boot into buildroot initramfs where you can access eMMC and deploy your custom built distribution. Login using root as username and blank password.


### Step 6: Prepare Switch Storage

Format the switch's internal storage partitions for your new distribution:

```bash
# Make sure to be familiar with your eMMC partitions

# Format root partition
mkfs.ext4 /dev/mmcblk0p6

# Make necessary mounting points and mount USB drive and eMMC
mkdir -p /mnt/mmc /mnt/usb

mount /dev/mmcblk0p6 /mnt/mmc

mkdir -p /mnt/mmc/boot

mount /dev/sda1 /mnt/usb
```

### Step 7: Deploy the Distribution

**Install Buildroot Kernel**: Deploy the hardware-optimized kernel image (without initramfs) built from [Buildroot External Novarq](https://github.com/novarq/buildroot-external-novarq). This kernel provides the essential hardware drivers and boot capabilities your custom distribution requires.

```bash
# Install kernel image
cp /mnt/usb/uImage-lan969x.itb /mnt/mmc/boot/
```

**Deploy Custom Root Filesystem**: Extract the debootstrapped distribution archive created in the earlier the Root Filesystem build process. This  transforms your switch into a full-featured Linux system.

```bash
# Deploy root filesystem
tar --same-owner -pxmf /mnt/usb/tactical1000-[distro].tar.xz -C /mnt/mmc

# Sync and unmount
sync
umount /mnt/mmc /mnt/usb
```

### Step 7: Boot Your Custom Distribution

Reboot the switch to launch your newly deployed distribution:

```bash
# Reboot the system
reboot
```
Access the U-Boot prompt (interrupt boot sequence) once again to set the environmnet which will boot from eMMC.

```bash
# Set the environmnet to boot from eMMC
setenv bootargs 'console=ttyAT0,115200 root=/dev/mmcblk0p6 rootwait rw'
setenv bootcmd 'ext4load mmc 0:6 ${loadaddr} boot/uImage-lan969x.itb; bootm'

# save the u-boot environment
saveenv

# Finally boot into new system
boot
```

### Step 8: Powercycle the switch

If all went well now your switch will boot into your custom Linux environment with full access to the distribution's package ecosystem and development tools. 

Login using the credentials established during build of the Root Filesystem (Step 2).
