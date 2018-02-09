#!/bin/bash
# Copyright 2016 VMware, Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Build the appliance filesystem ontop of the base

# exit on failure and configure debug, include util functions
set -e && [ -n "$DEBUG" ] && set -x
DIR=$(dirname $(readlink -f "$0"))
. $DIR/base/utils.sh

function usage() {
echo "Usage: $0 -p staged-package(tgz) -b binary-dir" 1>&2
exit 1
}

while getopts "p:b:" flag
do
    case $flag in

        p)
            # Required. Package name
            PACKAGE="$OPTARG"
            ;;

        b)
            # Required. Target for iso and source for components
            BIN="$OPTARG"
            ;;

        *)
            usage
            ;;
    esac
done

shift $((OPTIND-1))

# check there were no extra args and the required ones are set
if [ ! -z "$*" -o -z "$PACKAGE" -o -z "${BIN}" ]; then
    usage
fi

PKGDIR=$(mktemp -d)

# unpackage base package
unpack $PACKAGE $PKGDIR

#################################################################
# Above: arg parsing and setup
# Below: the image authoring
#################################################################

# sysctl
cp ${DIR}/appliance/sysctl.conf $(rootfs_dir $PKGDIR)/etc/

## systemd configuration
# create systemd vic target
cp ${DIR}/appliance/vic.target $(rootfs_dir $PKGDIR)/etc/systemd/system/
cp ${DIR}/appliance/*.service $(rootfs_dir $PKGDIR)/etc/systemd/system/
cp ${DIR}/appliance/*-setup $(rootfs_dir $PKGDIR)/etc/systemd/scripts

mkdir -p $(rootfs_dir $PKGDIR)/etc/systemd/system/vic.target.wants
ln -s /etc/systemd/system/vic-init.service $(rootfs_dir $PKGDIR)/etc/systemd/system/vic.target.wants/
ln -s /etc/systemd/system/nat.service $(rootfs_dir $PKGDIR)/etc/systemd/system/vic.target.wants/
ln -s /etc/systemd/system/permissions.service $(rootfs_dir $PKGDIR)/etc/systemd/system/vic.target.wants/
ln -s /lib/systemd/system/multi-user.target $(rootfs_dir $PKGDIR)/etc/systemd/system/vic.target.wants/

# change the default systemd target to launch VIC
chroot $(rootfs_dir $PKGDIR) systemctl set-default vic.target

# seal the systemd machine id
# this prevents systemd from regenerating units on first boot
chroot $(rootfs_dir $PKGDIR) systemd-machine-id-setup
> $(rootfs_dir $PKGDIR)/etc/machine-id

# disable networkd given we manage the link state directly
chroot $(rootfs_dir $PKGDIR) systemctl disable \
    systemd-networkd.service systemd-networkd.socket \
    systemd-resolved.service \
    systemd-timesyncd.service

# do not use the systemd dhcp client
rm -f $(rootfs_dir $PKGDIR)/etc/systemd/network/*
cp ${DIR}/base/no-dhcp.network $(rootfs_dir $PKGDIR)/etc/systemd/network/

# do not use the default iptables rules - nat-setup supplants this
rm -f $(rootfs_dir $PKGDIR)/etc/systemd/network/*

#
# Set up component users
#

# HACK: work around missing user utils with toybox
echo "#!/bin/true" > $(rootfs_dir $PKGDIR)/bin/no-op
chmod a+x $(rootfs_dir $PKGDIR)/bin/no-op
ln -s /bin/no-op $(rootfs_dir $PKGDIR)/bin/groupadd
ln -s /bin/no-op $(rootfs_dir $PKGDIR)/bin/useradd
ln -s /bin/no-op $(rootfs_dir $PKGDIR)/bin/usermod
mkdir -p $(rootfs_dir $PKGDIR)/home/vicadmin
echo "vicadmin:x:1000:" >> $(rootfs_dir $PKGDIR)/etc/group 
echo "vic:x:1001:vicadmin" >> $(rootfs_dir $PKGDIR)/etc/group
echo "vicadmin::1000:1000::/home/vicadmin:/bin/false" >> $(rootfs_dir $PKGDIR)/etc/passwd
# END HACK

# HACK: address missing resolv.con
# unclear why this isn't created by createBindSrcTarget
chroot $(rootfs_dir $PKGDIR) touch /etc/resolv.conf
# END HACK

# toolbox errors with usermod and groupadd
chroot $(rootfs_dir $PKGDIR) groupadd -g 1000 vicadmin || true
chroot $(rootfs_dir $PKGDIR) useradd -u 1000 -g 1000 -G systemd-journal -m -d /home/vicadmin -s /bin/false vicadmin || true

# Group vic should be used to run all VIC related services.
chroot $(rootfs_dir $PKGDIR) groupadd -g 1001 vic || true
chroot $(rootfs_dir $PKGDIR) usermod -a -G vic vicadmin || true

cp -R ${DIR}/vicadmin/* $(rootfs_dir $PKGDIR)/home/vicadmin
chown -R 1000:1000 $(rootfs_dir $PKGDIR)/home/vicadmin

# so vicadmin can read the system journal via journalctl
install -m 755 -d $(rootfs_dir $PKGDIR)/etc/tmpfiles.d
echo "m  /var/log/journal/%m/system.journal 2755 root systemd-journal - -" > $(rootfs_dir $PKGDIR)/etc/tmpfiles.d/systemd.conf

chroot $(rootfs_dir $PKGDIR) mkdir -p /var/run/lock
chroot $(rootfs_dir $PKGDIR) chmod 1777 /var/run/lock
chroot $(rootfs_dir $PKGDIR) touch /var/run/lock/logrotate_run.lock
chroot $(rootfs_dir $PKGDIR) chown root:vic /var/run/lock/logrotate_run.lock
chroot $(rootfs_dir $PKGDIR) chmod 0660 /var/run/lock/logrotate_run.lock

## main VIC components
# tether based init
cp ${BIN}/vic-init $(rootfs_dir $PKGDIR)/sbin/vic-init

cp ${BIN}/{docker-engine-server,port-layer-server,vicadmin} $(rootfs_dir $PKGDIR)/sbin/
cp ${BIN}/unpack $(rootfs_dir $PKGDIR)/bin/

# Generate the ISO
# Select systemd for our init process
generate_iso $PKGDIR $BIN/appliance.iso /lib/systemd/systemd
