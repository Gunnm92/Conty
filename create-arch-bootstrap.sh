#!/usr/bin/env bash

# Dependencies: curl tar gzip grep coreutils
# Root rights are required

########################################################################

# Package groups
audio_pkgs="alsa-lib lib32-alsa-lib alsa-plugins lib32-alsa-plugins libpulse \
	lib32-libpulse alsa-tools alsa-utils pipewire lib32-pipewire pipewire-pulse pipewire-jack lib32-pipewire-jack"

core_pkgs="xorg-xwayland qt6-wayland wayland \
	lib32-wayland qt5-wayland xorg-server-xephyr gamescope"

video_pkgs="mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon \
	vulkan-intel lib32-vulkan-intel \
	vulkan-icd-loader lib32-vulkan-icd-loader vulkan-mesa-layers \
	lib32-vulkan-mesa-layers libva-mesa-driver lib32-libva-mesa-driver \
	libva-intel-driver lib32-libva-intel-driver intel-media-driver \
	mesa-utils vulkan-tools libva-utils lib32-mesa-utils"

wine_pkgs="wine-staging winetricks-git wine-nine wineasio \
	freetype2 lib32-freetype2 libxft lib32-libxft \
	flex lib32-flex fluidsynth lib32-fluidsynth \
	libxrandr lib32-libxrandr xorg-xrandr libldap lib32-libldap \
	mpg123 lib32-mpg123 libxcomposite lib32-libxcomposite \
	libxi lib32-libxi libxinerama lib32-libxinerama libxss lib32-libxss \
	libxslt lib32-libxslt openal lib32-openal \
	krb5 lib32-krb5 libpulse lib32-libpulse alsa-plugins \
	lib32-alsa-plugins alsa-lib lib32-alsa-lib gnutls lib32-gnutls \
	giflib lib32-giflib gst-libav gst-plugin-pipewire gst-plugins-ugly \
	gst-plugins-bad gst-plugins-bad-libs \
	gst-plugins-base-libs lib32-gst-plugins-base-libs gst-plugins-base lib32-gst-plugins-base \
	gst-plugins-good lib32-gst-plugins-good gstreamer lib32-gstreamer \
	libpng lib32-libpng v4l-utils lib32-v4l-utils \
	libgpg-error lib32-libgpg-error libjpeg-turbo lib32-libjpeg-turbo \
	libgcrypt lib32-libgcrypt ncurses lib32-ncurses ocl-icd lib32-ocl-icd 
	libxcrypt-compat lib32-libxcrypt-compat libva lib32-libva sqlite lib32-sqlite \
	gtk3 lib32-gtk3 vulkan-icd-loader lib32-vulkan-icd-loader \
	sdl2 lib32-sdl2 vkd3d lib32-vkd3d libgphoto2 \
	openssl-1.1 lib32-openssl-1.1 libnm lib32-libnm \
	cabextract wget gamemode lib32-gamemode mangohud lib32-mangohud"

devel_pkgs="base-devel git meson mingw-w64-gcc cmake"

gaming_pkgs="lutris steam steam-native-runtime steamtinkerlaunch minigalaxy \
	gamehub legendary prismlauncher bottles playonlinux obs-studio \
	retroarch retroarch-assets-ozone libretro-beetle-psx-hw sunshine \
	libretro-blastem libretro-bsnes libretro-dolphin duckstation \
	libretro-gambatte libretro-melonds libretro-mgba libretro-nestopia \
	libretro-parallel-n64 libretro-pcsx2 libretro-picodrive libretro-ppsspp \
	libretro-retrodream libretro-yabause pcsx2-avx-git"

extra_pkgs="nano ttf-dejavu ttf-liberation firefox mpv geany pcmanfm \
	htop qbittorrent speedcrunch gpicview file-roller openbox lxterminal \
	yt-dlp minizip nautilus genymotion jre17-openjdk"

# Packages to install
# You can add packages that you want and remove packages that you don't need
# Apart from packages from the official Arch repos, you can also specify
# packages from the Chaotic-AUR repo
export packagelist="${audio_pkgs} ${core_pkgs} ${video_pkgs} ${wine_pkgs} ${extra_pkgs}"

# If you want to install AUR packages, specify them in this variable
export aur_packagelist="faugus-launcher-git"

# ALHP is a repository containing packages from the official Arch Linux
# repos recompiled with -O3, LTO and optimizations for modern CPUs for
# better performance
#
# When this repository is enabled, most of the packages from the official
# Arch Linux repos will be replaced with their optimized versions from ALHP
#
# Set this variable to true, if you want to enable this repository
enable_alhp_repo="false"

# Feature levels for ALHP. Available feature levels are 2 and 3
# For level 2 you need a CPU with SSE4.2 instructions
# For level 3 you need a CPU with AVX2 instructions
alhp_feature_level="2"

########################################################################

if [ $EUID != 0 ]; then
	echo "Root rights are required!"

	exit 1
fi

if ! command -v curl 1>/dev/null; then
	echo "curl is required!"
	exit 1
fi

if ! command -v gzip 1>/dev/null; then
	echo "gzip is required!"
	exit 1
fi

if ! command -v grep 1>/dev/null; then
	echo "grep is required!"
	exit 1
fi

if ! command -v sha256sum 1>/dev/null; then
	echo "sha256sum is required!"
	exit 1
fi

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

mount_chroot () {
	# First unmount just in case
	umount -Rl "${bootstrap}"

	mount --bind "${bootstrap}" "${bootstrap}"
	mount -t proc /proc "${bootstrap}"/proc
	mount --bind /sys "${bootstrap}"/sys
	mount --make-rslave "${bootstrap}"/sys
	mount --bind /dev "${bootstrap}"/dev
	mount --bind /dev/pts "${bootstrap}"/dev/pts
	mount --bind /dev/shm "${bootstrap}"/dev/shm
	mount --make-rslave "${bootstrap}"/dev

	rm -f "${bootstrap}"/etc/resolv.conf
	cp /etc/resolv.conf "${bootstrap}"/etc/resolv.conf

	mkdir -p "${bootstrap}"/run/shm
}

unmount_chroot () {
	umount -l "${bootstrap}"
	umount "${bootstrap}"/proc
	umount "${bootstrap}"/sys
	umount "${bootstrap}"/dev/pts
	umount "${bootstrap}"/dev/shm
	umount "${bootstrap}"/dev
}

run_in_chroot () {
	if [ -n "${CHROOT_AUR}" ]; then
		chroot --userspec=aur:aur "${bootstrap}" /usr/bin/env LANG=en_US.UTF-8 TERM=xterm PATH="/bin:/sbin:/usr/bin:/usr/sbin" "$@"
	else
		chroot "${bootstrap}" /usr/bin/env LANG=en_US.UTF-8 TERM=xterm PATH="/bin:/sbin:/usr/bin:/usr/sbin" "$@"
	fi
}

install_packages () {
	echo "Checking if packages are present in the repos, please wait..."
	for p in ${packagelist}; do
		if pacman -Sp "${p}" &>/dev/null; then
			good_pkglist="${good_pkglist} ${p}"
		else
			bad_pkglist="${bad_pkglist} ${p}"
		fi
	done

	if [ -n "${bad_pkglist}" ]; then
		echo ${bad_pkglist} > /opt/bad_pkglist.txt
	fi

	for i in {1..10}; do
		if pacman --noconfirm --needed -S ${good_pkglist}; then
			good_install=1
			break
		fi
	done

	if [ -z "${good_install}" ]; then
		echo > /opt/pacman_failed.txt
	fi
}

install_aur_packages () {
	cd /home/aur

	echo "Checking if packages are present in the AUR, please wait..."
	for p in ${aur_pkgs}; do
		if ! yay -a -G "${p}" &>/dev/null; then
			bad_aur_pkglist="${bad_aur_pkglist} ${p}"
		fi
	done

	if [ -n "${bad_aur_pkglist}" ]; then
		echo ${bad_aur_pkglist} > /home/aur/bad_aur_pkglist.txt
	fi

	for i in {1..10}; do
		if yes | yay --needed --removemake --builddir /home/aur -a -S ${aur_pkgs}; then
			break
		fi
	done
}

generate_pkg_licenses_file () {
	for p in $(pacman -Q | cut -d' ' -f1); do
		echo -n $(pacman -Qi "${p}" | grep -E 'Name|Licenses' | cut -d ":" -f 2) >>/pkglicenses.txt
		echo >>/pkglicenses.txt
	done
}

generate_localegen () {
	cat <<EOF > locale.gen
fr_FR.UTF-8 UTF-8
EOF
}

generate_mirrorlist () {
	cat <<EOF > mirrorlist
Server = https://mirror1.sl-chat.ru/archlinux/\$repo/os/\$arch
Server = https://mirror3.sl-chat.ru/archlinux/\$repo/os/\$arch
Server = https://us.mirrors.cicku.me/archlinux/\$repo/os/\$arch
Server = https://mirror.osbeck.com/archlinux/\$repo/os/\$arch
Server = https://md.mirrors.hacktegic.com/archlinux/\$repo/os/\$arch
Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch
Server = https://mirror.qctronics.com/archlinux/\$repo/os/\$arch
Server = https://arch.mirror.constant.com/\$repo/os/\$arch
Server = https://america.mirror.pkgbuild.com/\$repo/os/\$arch
Server = https://mirror.tmmworkshop.com/archlinux/\$repo/os/\$arch
EOF
}

cd "${script_dir}" || exit 1

bootstrap="${script_dir}"/root.x86_64

curl -#LO 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
curl -#LO 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

if [ ! -s chaotic-keyring.pkg.tar.zst ] || [ ! -s chaotic-mirrorlist.pkg.tar.zst ]; then
	echo "Seems like Chaotic-AUR keyring or mirrorlist is currently unavailable"
	echo "Please try again later"
	exit 1
fi

bootstrap_urls=("arch.hu.fo" \
		"mirror.cyberbits.eu" \
		"mirror.osbeck.com" \
		"mirror.lcarilla.de" \
		"mirror.moson.org" \
  		"mirror.f4st.host")

echo "Downloading Arch Linux bootstrap"

for link in "${bootstrap_urls[@]}"; do
	curl -#LO "https://${link}/archlinux/iso/latest/archlinux-bootstrap-x86_64.tar.zst"
	curl -#LO "https://${link}/archlinux/iso/latest/sha256sums.txt"

	if [ -s sha256sums.txt ]; then
		grep bootstrap-x86_64 sha256sums.txt > sha256.txt

		echo "Verifying the integrity of the bootstrap"
		if sha256sum -c sha256.txt &>/dev/null; then
			bootstrap_is_good=1
			break
		fi
	fi

	echo "Download failed, trying again with different mirror"
done

if [ -z "${bootstrap_is_good}" ]; then
	echo "Bootstrap download failed or its checksum is incorrect"
	exit 1
fi

rm -rf "${bootstrap}"
tar xf archlinux-bootstrap-x86_64.tar.zst
rm archlinux-bootstrap-x86_64.tar.zst sha256sums.txt sha256.txt

mount_chroot

generate_localegen

if command -v reflector 1>/dev/null; then
	echo "Generating mirrorlist..."
	reflector --connection-timeout 10 --download-timeout 10 --protocol https --score 10 --sort rate --save mirrorlist
	reflector_used=1
else
	generate_mirrorlist
fi

rm "${bootstrap}"/etc/locale.gen
mv locale.gen "${bootstrap}"/etc/locale.gen

rm "${bootstrap}"/etc/pacman.d/mirrorlist
mv mirrorlist "${bootstrap}"/etc/pacman.d/mirrorlist

{
	echo
	echo "[multilib]"
	echo "Include = /etc/pacman.d/mirrorlist"
} >> "${bootstrap}"/etc/pacman.conf

run_in_chroot pacman-key --init
echo "keyserver hkps://keyserver.ubuntu.com" >> "${bootstrap}"/etc/pacman.d/gnupg/gpg.conf
run_in_chroot pacman-key --populate archlinux

# Add Chaotic-AUR repo
run_in_chroot pacman-key --recv-key 3056513887B78AEB
run_in_chroot pacman-key --lsign-key 3056513887B78AEB

mv chaotic-keyring.pkg.tar.zst chaotic-mirrorlist.pkg.tar.zst "${bootstrap}"/opt
run_in_chroot pacman --noconfirm -U /opt/chaotic-keyring.pkg.tar.zst /opt/chaotic-mirrorlist.pkg.tar.zst
rm "${bootstrap}"/opt/chaotic-keyring.pkg.tar.zst "${bootstrap}"/opt/chaotic-mirrorlist.pkg.tar.zst

{
	echo
	echo "[chaotic-aur]"
	echo "Include = /etc/pacman.d/chaotic-mirrorlist"
} >> "${bootstrap}"/etc/pacman.conf

# The ParallelDownloads feature of pacman
# Speeds up packages installation, especially when there are many small packages to install
sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 3/g' "${bootstrap}"/etc/pacman.conf

# Do not install unneeded files (man pages and Nvidia firmwares)
sed -i 's/#NoExtract   =/NoExtract   = usr\/lib\/firmware\/nvidia\/\* usr\/share\/man\/\*/' "${bootstrap}"/etc/pacman.conf

run_in_chroot pacman -Sy archlinux-keyring --noconfirm
run_in_chroot pacman -Su --noconfirm

if [ "${enable_alhp_repo}" = "true" ]; then
	if [ "${alhp_feature_level}" -gt 2 ]; then
		alhp_feature_level=3
	else
		alhp_feature_level=2
	fi

	run_in_chroot pacman --noconfirm --needed -S alhp-keyring alhp-mirrorlist
	sed -i "s/#\[multilib\]/#/" "${bootstrap}"/etc/pacman.conf
	sed -i "s/\[core\]/\[core-x86-64-v${alhp_feature_level}\]\nInclude = \/etc\/pacman.d\/alhp-mirrorlist\n\n\[extra-x86-64-v${alhp_feature_level}\]\nInclude = \/etc\/pacman.d\/alhp-mirrorlist\n\n\[core\]/" "${bootstrap}"/etc/pacman.conf
	sed -i "s/\[multilib\]/\[multilib-x86-64-v${alhp_feature_level}\]\nInclude = \/etc\/pacman.d\/alhp-mirrorlist\n\n\[multilib\]/" "${bootstrap}"/etc/pacman.conf
	run_in_chroot pacman -Syu --noconfirm
fi

date -u +"%d-%m-%Y %H:%M (DMY UTC)" > "${bootstrap}"/version

# These packages are required for the self-update feature to work properly
run_in_chroot pacman --noconfirm --needed -S base reflector squashfs-tools fakeroot

# Regenerate the mirrorlist with reflector if reflector was not used before
if [ -z "${reflector_used}" ]; then
	echo "Generating mirrorlist..."
	run_in_chroot reflector --connection-timeout 10 --download-timeout 10 --protocol https --score 10 --sort rate --save /etc/pacman.d/mirrorlist
 	run_in_chroot pacman -Syu --noconfirm
fi

export -f install_packages
run_in_chroot bash -c install_packages

if [ -f "${bootstrap}"/opt/pacman_failed.txt ]; then
	unmount_chroot
	echo "Pacman failed to install some packages"
	exit 1
fi

if [ -n "${aur_packagelist}" ]; then
	run_in_chroot pacman --noconfirm --needed -S base-devel yay
	run_in_chroot useradd -m -G wheel aur
	echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" >> "${bootstrap}"/etc/sudoers

	for p in ${aur_packagelist}; do
		aur_pkgs="${aur_pkgs} aur/${p}"
	done
	export aur_pkgs

	export -f install_aur_packages
	CHROOT_AUR=1 HOME=/home/aur run_in_chroot bash -c install_aur_packages
	mv "${bootstrap}"/home/aur/bad_aur_pkglist.txt "${bootstrap}"/opt
	rm -rf "${bootstrap}"/home/aur
fi

run_in_chroot locale-gen

echo "Generating package info, please wait..."

# Generate a list of installed packages
run_in_chroot pacman -Q > "${bootstrap}"/pkglist.x86_64.txt

# Generate a list of licenses of installed packages
export -f generate_pkg_licenses_file
run_in_chroot bash -c generate_pkg_licenses_file

unmount_chroot

# Clear pacman package cache
rm -f "${bootstrap}"/var/cache/pacman/pkg/*

# Create some empty files and directories
# This is needed for bubblewrap to be able to bind real files/dirs to them
# later in the conty-start.sh script
mkdir "${bootstrap}"/media
mkdir -p "${bootstrap}"/usr/share/steam/compatibilitytools.d
touch "${bootstrap}"/etc/asound.conf
touch "${bootstrap}"/etc/localtime
chmod 755 "${bootstrap}"/root

# Enable full font hinting
rm -f "${bootstrap}"/etc/fonts/conf.d/10-hinting-slight.conf
ln -s /usr/share/fontconfig/conf.avail/10-hinting-full.conf "${bootstrap}"/etc/fonts/conf.d

# Add some wine version
# Configuration des versions, architectures et répertoires
WINE_VERSIONS=("9.22" "7.20")
PROTON_VERSION="proton-exp-9.0"
GE_CUSTOM_VERSION="GE-Custom9-20"
ARCHITECTURE="${ARCHITECTURE:-amd64}"
BASE_WINE_URL="https://github.com/Kron4ek/Wine-Builds/releases/download"
BASE_GE_CUSTOM_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton9-20/GE-Proton9-20.tar.gz"

# Répertoires
TMP_DIR="${bootstrap:-/tmp}/tmp"
DEST_DIR="${bootstrap:-/usr/local}/usr/local"
SYMLINK_DIR="/usr/bin" # Modifié pour correspondre à /usr/bin

# Création des répertoires nécessaires
mkdir -p "${TMP_DIR}" "${SYMLINK_DIR}"

# Fonction pour valider l'URL
        exit 1
    fi
} est inaccessible."
        exit 1
    fi
}

# Fonction générique pour télécharger, extraire et installer
download_and_install() {
    local NAME=$1
    local VERSION=$2
    local URL=$3
    local EXT=$4
    local DEST=$5

    
    local TARGET_FILE="${TMP_DIR}/${NAME}-${VERSION}.${EXT}"

    echo "Téléchargement de ${NAME} version ${VERSION}..."
    if ! curl -#L "${URL}" -o "${TARGET_FILE}"; then then
        echo "Erreur : Échec du téléchargement de ${NAME} version ${VERSION}."
        exit 1
    fi

    echo "Extraction de ${NAME} version ${VERSION}..."
    if [[ "${EXT}" == "tar.xz" || "${EXT}" == "tar.gz" ]]; then
        tar -xf "${TARGET_FILE}" -C "${TMP_DIR}"
    else
        echo "Format de fichier non pris en charge : ${EXT}"
        exit 1
    fi

    local EXTRACTED_DIR=$(find "${TMP_DIR}" -mindepth 1 -maxdepth 1 -type d | head -n 1)
    if [ ! -d "${EXTRACTED_DIR}" ]; then
        echo "Erreur : Échec de l'extraction de ${NAME} version ${VERSION}."
        exit 1
    fi

    echo "Installation de ${NAME} version ${VERSION} dans ${DEST}..."
    mkdir -p "${DEST}/${NAME}-${VERSION}"
    cp -r "${EXTRACTED_DIR}"/* "${DEST}/${NAME}-${VERSION}/"

    echo "Création d'un lien symbolique pour ${NAME} version ${VERSION}..."
    if [ -x "${DEST}/${NAME}-${VERSION}/bin/wine" ]; then
        if [ -L "${SYMLINK_DIR}/${NAME}-${VERSION}" ]; then
            echo "Attention : Le lien symbolique ${SYMLINK_DIR}/${NAME}-${VERSION} existe déjà. Mise à jour..."
            rm -f "${SYMLINK_DIR}/${NAME}-${VERSION}"
        fi
        ln -sf "${DEST}/${NAME}-${VERSION}/bin/wine" "${SYMLINK_DIR}/${NAME}-${VERSION}"
        echo "Lien symbolique créé : ${SYMLINK_DIR}/${NAME}-${VERSION}"
    else
        echo "Erreur : Le binaire wine est introuvable ou non exécutable."
    fi

    rm -rf "${EXTRACTED_DIR}" "${TARGET_FILE}"
}

# Nettoyage final
cleanup() {
    echo "Nettoyage des fichiers temporaires..."
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

# Installation des versions de Wine
for WINE_VERSION in "${WINE_VERSIONS[@]}"; do
    WINE_URL="${BASE_WINE_URL}/${WINE_VERSION}/wine-${WINE_VERSION}-staging-${ARCHITECTURE}.tar.xz"
    download_and_install "wine" "${WINE_VERSION}" "${WINE_URL}" "tar.xz" "${DEST_DIR}"
done

# Installation de Proton Experimental
PROTON_URL="${BASE_WINE_URL}/${PROTON_VERSION}/wine-${PROTON_VERSION}-${ARCHITECTURE}.tar.xz"
download_and_install "proton-exp" "${PROTON_VERSION}" "${PROTON_URL}" "tar.xz" "${DEST_DIR}"

# Installation de GE-Custom
GE_CUSTOM_URL="${BASE_GE_CUSTOM_URL}/${GE_CUSTOM_VERSION}/${GE_CUSTOM_VERSION}.tar.gz"
download_and_install "ge-custom" "${GE_CUSTOM_VERSION}" "${GE_CUSTOM_URL}" "tar.gz" "${DEST_DIR}"

# Nettoyage final
echo "Installation terminée ! Liens symboliques créés dans ${SYMLINK_DIR}."

clear
echo "Done"

if [ -f "${bootstrap}"/opt/bad_pkglist.txt ]; then
	echo
	echo "These packages are not in the repos and have not been installed:"
	cat "${bootstrap}"/opt/bad_pkglist.txt
	rm "${bootstrap}"/opt/bad_pkglist.txt
fi

if [ -f "${bootstrap}"/opt/bad_aur_pkglist.txt ]; then
	echo
	echo "These packages are either not in the AUR or yay failed to download their"
	echo "PKGBUILDs:"
	cat "${bootstrap}"/opt/bad_aur_pkglist.txt
	rm "${bootstrap}"/opt/bad_aur_pkglist.txt
fi
