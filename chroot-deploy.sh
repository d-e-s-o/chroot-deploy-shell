#!/bin/bash

#/***************************************************************************
# *   Copyright (C) 2014 Daniel Mueller (deso@posteo.net)                   *
# *                                                                         *
# *   This program is free software: you can redistribute it and/or modify  *
# *   it under the terms of the GNU General Public License as published by  *
# *   the Free Software Foundation, either version 3 of the License, or     *
# *   (at your option) any later version.                                   *
# *                                                                         *
# *   This program is distributed in the hope that it will be useful,       *
# *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
# *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
# *   GNU General Public License for more details.                          *
# *                                                                         *
# *   You should have received a copy of the GNU General Public License     *
# *   along with this program.  If not, see <http://www.gnu.org/licenses/>. *
# ***************************************************************************/

if [ $# -ne 1 ]; then
  echo "Invalid parameter count."
  echo "Usage: ${0} <chroot-tar-bz2-archive>"
  exit 1
fi

# TODO: We need proper error handling, i.e., we should fail on all
#       errors ('set -e') and undo all previous modifications.
DEPLOY_DIR="/tmp"
ARCHIVE=$(realpath "${1}")
CHROOT="${DEPLOY_DIR}/$(basename --suffix .tar.bz2 ${ARCHIVE})"

if [ -d "${CHROOT}" ]; then
  echo "Directory already exists: ${CHROOT}."
  echo "Stopping."
  exit 1
fi

mkdir -p "${CHROOT}"
cd "${CHROOT}"

# Note: We assume the package contains no actual (named) root directory.
tar -xjf "${ARCHIVE}"

mkdir "${CHROOT}/dev"
mkdir "${CHROOT}/sys"
mkdir "${CHROOT}/usr/portage"

cp -L /etc/resolv.conf ${CHROOT}/etc/

mount -t proc proc ${CHROOT}/proc
mount --bind /sys ${CHROOT}/sys
mount --bind /dev ${CHROOT}/dev
mount --bind /usr/portage ${CHROOT}/usr/portage
mount --bind /tmp ${CHROOT}/tmp

chroot ${CHROOT} /bin/su --login deso -c '/bin/env PS1="(chroot) \[\033[01;32m\]\u@\h\[\033[01;34m\] \w \$\[\033[00m\] " bash --norc -i'

umount ${CHROOT}/tmp
umount ${CHROOT}/usr/portage
umount ${CHROOT}/proc
umount ${CHROOT}/sys
umount ${CHROOT}/dev

rm -rf "${CHROOT}"
