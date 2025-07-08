#!/bin/bash
#
# requires debootstrap qemu-aarch64-static chroot tar xz
#          
#
set -e

# Fixed list of essential packages to always install
FIXED_PACKAGES="tar xz-utils"

function usage {
	cat <<EOF
usage: $0 <family> <distro> [packages...]

	family: tactical1000
	distro: noble, bookworm
	packages: optional space-separated list of additional packages to install

Fixed packages always installed: $FIXED_PACKAGES

Examples:
	$0 tactical1000 noble
	$0 tactical1000 bookworm curl vim git

EOF

	exit 1
}

function required {
	local cmd=$1

	if ! [ -x "$(command -v $cmd)" ]; then
		echo "Error: $cmd required"
		exit 1
	fi
}

# function to validate packages exist in repositories
function validate_packages {
	local packages="$1"
	local mirror="$2"
	local dist="$3"
	local arch="$4"
	
	if [ -z "$packages" ]; then
		return 0
	fi
	
	echo "Validating packages: $packages"
	
	# Create temporary directory for validation
	local temp_dir=$(mktemp -d)
	local temp_sources="$temp_dir/sources.list"
	
	# Create temporary sources.list for validation
	case "$dist" in
		noble)
			cat > "$temp_sources" <<EOF
deb $mirror $dist main restricted universe multiverse
EOF
		;;
		bookworm)
			cat > "$temp_sources" <<EOF
deb $mirror $dist main contrib non-free
EOF
		;;
	esac
	
	# Update package cache for validation
	echo "Updating package cache for validation..."
	apt update -o Dir::Etc::SourceList="$temp_sources" -q
	
	# Check each package
	for pkg in $packages; do
		echo "Checking package: $pkg"
		if ! apt-cache show $pkg >/dev/null 2>&1; then
			echo "Error: Package '$pkg' not found in repositories"
			echo "Available similar packages:"
			apt-cache search $pkg | head -5
			rm -rf "$temp_dir"
			exit 1
		else
			echo "✓ Package '$pkg' found"
		fi
	done
	
	# Cleanup
	rm -rf "$temp_dir"
	echo "All packages validated successfully"
}

# function to prompt for root password
function get_root_password {
	echo ""
	echo "Setting up root password for the rootfs..."
	read -s -p "Enter root password: " ROOT_PASSWD
	echo ""
	read -s -p "Confirm root password: " ROOT_PASSWD_CONFIRM
	echo ""
	
	if [ "$ROOT_PASSWD" != "$ROOT_PASSWD_CONFIRM" ]; then
		echo "Error: Passwords do not match"
		exit 1
	fi
	
	if [ -z "$ROOT_PASSWD" ]; then
		echo "Error: Password cannot be empty"
		exit 1
	fi
	
	echo "Root password set successfully"
}

# second stage setup function
# all commands in this function gets executed after chroot
function second_stage {
	set -e
	echo "Starting second stage"
	export LANG=C
	/debootstrap/debootstrap --second-stage

case "$distro" in
	noble)
	# Add package src repos
	cat <<EOF >> /etc/apt/sources.list
deb-src http://ports.ubuntu.com/ubuntu-ports $distro main restricted universe multiverse
deb-src http://ports.ubuntu.com/ubuntu-ports ${distro}-updates main restricted universe multiverse
deb-src http://ports.ubuntu.com/ubuntu-ports ${distro}-security main restricted universe multiverse

EOF
	;;
	bookworm)
	cat <<EOF > /etc/apt/sources.list
deb https://deb.debian.org/debian/ $distro main contrib non-free
deb-src https://deb.debian.org/debian/ $distro main contrib non-free
deb https://security.debian.org/debian-security ${distro}-security main contrib non-free
deb-src https://security.debian.org/debian-security ${distro}-security main contrib non-free
deb https://deb.debian.org/debian/ ${distro}-updates main contrib non-free
deb-src https://deb.debian.org/debian/ ${distro}-updates main contrib non-free
EOF
	;;
esac

	# Set Hostname
	echo "${distro}-${family}" > /etc/hostname

	# root password
	[ -n "$ROOT_PASSWD" ] && {
		echo "Setting root passwd"
		echo "root:$ROOT_PASSWD" | chpasswd
	}

	# Install fixed packages and additional packages if specified
	echo "Installing fixed packages: $fixed_packages"
	apt update
	apt install -y $fixed_packages
	
	[ -n "$additional_packages" ] && {
		echo "Installing additional packages: $additional_packages"
		apt install -y $additional_packages
	}

case "$distro" in
	noble)
	echo "Configuring dhcp network"
	cat <<EOF >> /etc/netplan/config.yaml
network:
    version: 2
    renderer: networkd
    ethernets:
        $network_if:
            dhcp4: true
EOF
	;;
	bookworm)
	apt install -y systemd-timesyncd

	echo "Configuring dhcp network"
	cat <<EOF >> /etc/network/interfaces.d/dhcp
auto lo
iface lo inet loopback

auto $network_if
iface $network_if inet dhcp
EOF
	;;
esac

	# cleanup
	apt autoremove -y
	apt-get clean
	find /var/log -type f \
		\( -name "*.gz" -o -name "*.xz" -o -name "*.log" \) -delete
}

###### Main Script ######

# Check minimum arguments
if [ $# -lt 2 ]; then
	echo "Error: Missing required arguments"
	usage
fi

FAMILY=$1
DIST=$2
# Get additional packages (all arguments after first two)
shift 2
ADDITIONAL_PACKAGES="$*"

# Combine fixed packages with additional packages
ALL_PACKAGES="$FIXED_PACKAGES $ADDITIONAL_PACKAGES"

# default ENV

# check CMDLINE env
case "$FAMILY" in
	tactical1000)
		ARCH=arm64
		;;
	*) usage;;
esac

case "$DIST" in
	noble)
		MIRROR="http://ports.ubuntu.com/ubuntu-ports"
		;;
	bookworm)
		MIRROR="https://deb.debian.org/debian"
		;;
esac

echo "Using mirror: $MIRROR"
echo "Fixed packages to install: $FIXED_PACKAGES"
[ -n "$ADDITIONAL_PACKAGES" ] && echo "Additional packages to install: $ADDITIONAL_PACKAGES"

# check prerequisites
required debootstrap
required qemu-aarch64-static
required chroot
required tar
required xz

# Get root password from user
get_root_password

# Validate all packages before downloading
validate_packages "$ALL_PACKAGES" "$MIRROR" "$DIST" "$ARCH"

echo "✓ Pre-download checks passed OK"

outdir=${FAMILY}-${DIST}
echo "Creating ${outdir}..."

# first stage
debootstrap --arch=$ARCH --foreign $DIST $outdir $MIRROR

# install qemu to rootfs
cp /usr/bin/qemu-aarch64-static $outdir/usr/bin

#
# export functions and vars to make accessible to chroot env
#
export -f second_stage
export family=$FAMILY
export distro=$DIST
export ROOT_PASSWD
export fixed_packages="$FIXED_PACKAGES"
export additional_packages="$ADDITIONAL_PACKAGES"
export network_if=eth28
# make sure apt is non-interactive
export DEBIAN_FRONTEND=noninteractive

# second stage
chroot $outdir /bin/bash -c "second_stage"

# cleanup
rm $outdir/usr/bin/qemu-*-static # remove qemu

# create package manifest (name/ver) and package list (name)
echo "Creating package manifests"
dpkg -l --root=$outdir | grep ^ii | awk '{print $2 "\t" $3}' | sed s/:$ARCH// > ${outdir}.manifest; \
awk '{ print $1 }' ${outdir}.manifest > ${outdir}.packages

# build tarball
[ -n "$SKIP_TAR" ] || {
	echo "Building rootfs tarball ${outdir}.tar.xz ..."
	tar --numeric-owner -cJf ${outdir}.tar.xz -C $outdir .
}

exit 0
