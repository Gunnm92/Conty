#!/usr/bin/env bash

## Dependencies: fuse2 tar

# Prevent launching as root
if [ -z $ALLOW_ROOT ]; then
	if [ $EUID = 0 ]; then
		echo "Do not run this app as root!"
		echo
		echo "If you really need to run it as root, set ALLOW_ROOT env variable."
   
		exit 1
	fi
fi

# Full path to the script
script="$(readlink -f "${BASH_SOURCE[0]}")"

# Working directory where squashfs image will be mounted
# Default path: /tmp/scriptname_username_randomnumber
working_dir=/tmp/"$(basename "$0")"_"$(id -un)"_$RANDOM

# It's important to set correct sizes below, otherwise there will be
# a problem with mounting the squashfs image due to an incorrectly calculated offset.

# The size of this script
scriptsize=4178

# The size of the utils.tar archive
# utils.tar contains bwrap and squashfuse binaries
utilssize=1259520

# Offset where the squashfs image is stored
offset=$((scriptsize+utilssize))

if [ "$1" = "--help" ] || [ "$1" = "-h" ] || [ -z "$1" ]; then
    echo "Usage: ./conty.sh command command_arguments"
    echo
	echo "Arguments:"
	echo
	echo -e "-e \tExtract app files"
	echo -e "-o \tShow squashfs offset"
	
	echo
	echo "Environment variables:"
	echo
	echo -e "DISABLE_NET \tDisables network access"
	echo -e "SANDBOX \tEnables filesystem sandbox"
	echo -e "WHITELIST_DIRS \tWorks together with SANDBOX variable"
	echo -e "\t\tAllows access to directories specified (separated by space)"
	echo -e "\t\tin this variable. All specified directories must exist."
	echo -e "\t\tFor example, WHITELIST_DIRS=\"/home/username/.config /opt/bin\""
	echo
	echo "If you enable SANDBOX but don't set WHITELIST_DIRS, then"
	echo "no directories will be available at all. And a fake temporary HOME"
	echo "directory will be created inside the container."

	exit
elif [ "$1" = "-e" ]; then
	if command -v unsquashfs 1>/dev/null; then
		unsquashfs -o $offset -d "$(basename "$0")"_files "${script}"
	else
		echo "To extract the image install squashfs-tools."
	fi
	
	exit
elif [ "$1" = "-o" ]; then
	echo $offset
	
	exit
fi

# Check if FUSE2 is installed
if command -v fusermount 1>/dev/null; then
	fmount=fusermount
else
	echo "Please install fuse2 and run the app again"
	
	exit 1
fi

# Extract utils.tar
mkdir -p "${working_dir}"
tail -c +$((scriptsize+1)) "${script}" | head -c $utilssize > "${working_dir}"/utils.tar
tar -C "${working_dir}" -xf "${working_dir}"/utils.tar
rm "${working_dir}"/utils.tar

export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${working_dir}/utils"
sfuse="${working_dir}"/utils/squashfuse
bwrap="${working_dir}"/utils/bwrap

chmod +x "${sfuse}"
chmod +x "${bwrap}"

run_bwrap () {
	unshare="--unshare-user --unshare-pid --unshare-uts --unshare-cgroup"

	if [ -n "$DISABLE_NET" ]; then
		echo "Network is disabled"
		
		net="--unshare-net"
	fi
	
	if [ -n "$SANDBOX" ]; then
		echo "Filesystem sandbox is enabled"
	
		dirs="--tmpfs /home --tmpfs /opt --tmpfs /mnt --dir ${HOME}"

		if [ -n "$WHITELIST_DIRS" ]; then
			echo "Allowed directories: ${WHITELIST_DIRS}"
		
			for i in ${WHITELIST_DIRS}; do
				whitelist="${whitelist} --bind ${i} ${i}"
			done
		fi

		dirs="${dirs} ${whitelist}"
	else
		dirs="--bind /home /home --bind-try /mnt /mnt --bind-try /opt /opt"
	fi
	
	echo

	"${bwrap}" --ro-bind "${working_dir}"/mnt / \
			--dev-bind /dev /dev \
			--ro-bind /sys /sys \
			--bind /run /run \
			--bind /var /var \
			--bind /tmp /tmp \
			--ro-bind-try /etc/resolv.conf /etc/resolv.conf \
			--ro-bind-try /etc/hosts /etc/hosts \
			--ro-bind-try /etc/nsswitch.conf /etc/nsswitch.conf \
			--proc /proc \
			--ro-bind-try /usr/local /usr/local \
			${dirs} ${unshare} ${net} \
			--hostname Conty \
			--setenv PATH "/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin" \
			"$@"
}

# Mount boostrap image
mkdir -p "${working_dir}"/mnt
"${fmount}" -u "${working_dir}"/mnt 2>/dev/null || umount "${working_dir}"/mnt 2>/dev/null

"${sfuse}" -o offset="${offset}" "${script}" "${working_dir}"/mnt
if [ $? = 0 ]; then
	echo "Running Conty"
	run_bwrap "$@"

	"${fmount}" -uz "${working_dir}"/mnt 2>/dev/null || umount --lazy "${working_dir}"/mnt 2>/dev/null
else
	echo "Mounting the squashfs image failed!"
	
	exit 1
fi

rm -rf "${working_dir}"

exit