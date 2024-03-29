#!/bin/bash

#/***************************************************************************
# *   Copyright (C) 2014-2022 Daniel Mueller (deso@posteo.net)              *
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

# A tarball that can be deployed by the script can be created via:
# tar --xz -cpvf /tmp/gentoo-$(date '+%Y%m%d')-....tar.xz -C /tmp/stage3-*/ .

GETOPT="/usr/bin/getopt"
SHORT_OPTS="c:ru:"
LONG_OPTS="command:,remove,user:"
COMMAND=""
USER=""
REMOVE=""

RESULT=$("${GETOPT}" --options="${SHORT_OPTS}" --longoptions="${LONG_OPTS}" -- "${@}")

# If getopt failed we exit here. It will have printed a reasonable error
# message.
[ $? != 0 ] && exit 1

eval set -- "${RESULT}"

while true; do
  case "$1" in
    -c | --command ) COMMAND="${2}"; shift 2 ;;
    -r | --remove ) REMOVE="1"; shift 1 ;;
    -u | --user ) USER="${2}"; shift 2 ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

if [ $# -ne 1 ]; then
  echo "Invalid parameter count."
  echo "Usage: ${0} [-c/--command COMMAND] [-r/--remove] [-u/--user USER] <chroot-tar-xz-archive>"
  exit 1
fi

# TODO: We need proper error handling, i.e., we should fail on all
#       errors ('set -e') and undo all previous modifications.
TMP_DIR="/tmp"
DEPLOY_DIR="${TMP_DIR}"
ARCHIVE=$(realpath "${1}")
CHROOT="${DEPLOY_DIR}/$(basename --suffix .tar.xz ${ARCHIVE})"
BASE_SELF=$(basename "${0}" | sed 's![.]!_!g')
BASE_ARCHIVE=$(echo "${ARCHIVE}" | sed 's![/.]!_!g')
REFERENCE_FILE="${TMP_DIR}/${BASE_SELF}_${BASE_ARCHIVE}"
REFERENCE_LOCK="${REFERENCE_FILE}.lck"

test -f "${REFERENCE_FILE}" && REF_FILE_EXISTS=1 || REF_FILE_EXISTS=0
test -d "${CHROOT}"         && ROOT_DIR_EXISTS=1 || ROOT_DIR_EXISTS=0

atomicTouch() {
  mkdir "${1}" &> /dev/null
  echo "${?}"
}

lock() {
  while [ $(atomicTouch "${1}") -ne 0 ]; do
    sleep 1
  done
}

unlock() {
  rmdir "${1}"
}

incRefCount() {
  lock "${REFERENCE_LOCK}"

  if [ ${REF_FILE_EXISTS} -eq 0 ]; then
    echo 1 > "${REFERENCE_FILE}"
    echo 1
  else
    REFS=$(cat "${REFERENCE_FILE}")
    REFS=$((${REFS}+1))
    echo "${REFS}" > "${REFERENCE_FILE}"
    echo "${REFS}"
  fi

  unlock "${REFERENCE_LOCK}"
}

decAndGetRefCount() {
  lock "${REFERENCE_LOCK}"

  REFS=$(cat "${REFERENCE_FILE}")
  REFS=$((${REFS}-1))

  if [ ${REFS} -eq 0 ]; then
    rm "${REFERENCE_FILE}"
  else
    echo "${REFS}" > "${REFERENCE_FILE}"
  fi
  echo "${REFS}"

  unlock "${REFERENCE_LOCK}"
}


if [ "${REF_FILE_EXISTS}" -ne 0 -a "${ROOT_DIR_EXISTS}" -eq 0 ]; then
  # If a reference file exists but there is no root directory we must be
  # dealing with a stale file. Just remove it and move on.
  rm "${REFERENCE_FILE}"
  REF_FILE_EXISTS=0
fi

REFS=$(incRefCount)
if [ ${REFS} -eq 1 ]; then
  mkdir -p "${CHROOT}"
  cd "${CHROOT}"

  # Only extract the archive if the chroot directory does not exist.
  # That is to cater to the case where a user just exited all shells but
  # kept the chroot around for later. We do *not* want to overwrite its
  # contents.
  if [ "${ROOT_DIR_EXISTS}" -eq 0 ]; then
    # Note: We assume the package contains no actual (named) root
    #       directory as is the case for Gentoo's stage3 files.
    tar --xz -xpf "${ARCHIVE}"
  fi

  mkdir -p "${CHROOT}/dev"
  mkdir -p "${CHROOT}/sys"
  mkdir -p "${CHROOT}/var/db/repos"
  mkdir -p "${CHROOT}/tmp"
  mkdir -p "${CHROOT}/run"

  cp -L /etc/resolv.conf ${CHROOT}/etc/

  mount -t proc proc ${CHROOT}/proc
  mount --bind /sys ${CHROOT}/sys
  mount --bind /dev ${CHROOT}/dev
  mount --bind /var/db/repos ${CHROOT}/var/db/repos
  mount --bind /tmp ${CHROOT}/tmp
  mount --bind /run ${CHROOT}/run
fi

ARGS="/bin/su --login ${USER:-root}"
if [ -z "${COMMAND}" ]; then
  # If no command was provided we just spawn a shell.
  COMMAND='/bin/env PS1="(chroot) \[\033[01;32m\]\u@\h\[\033[01;34m\] \w \$\[\033[00m\] " bash --norc -i'
fi

chroot ${CHROOT} ${ARGS} --session-command "${COMMAND}"

# Check if we are the last one in the chroot and if so unmount everything and
# delete the directory.
REFS=$(decAndGetRefCount)
if [ ${REFS} -eq 0 ]; then
  umount ${CHROOT}/run
  umount ${CHROOT}/tmp
  umount ${CHROOT}/var/db/repos
  umount ${CHROOT}/proc
  umount ${CHROOT}/sys
  umount ${CHROOT}/dev

  if [ -n "${REMOVE}" ]; then
    # Note that the --one-file-system option does not in general care
    # about bind mounts but only about true file system borders. I.e.,
    # if there does still exist a bind mount in the directory it will be
    # not be deleted if and only if it is located on a different file
    # system.
    rm --one-file-system -rf "${CHROOT}"
  fi
fi
