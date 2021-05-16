#!/usr/bin/with-contenv bashio
# ==============================================================================
# Prepare the Samba service for running
# ==============================================================================
set -e

readonly CONF="/etc/samba/smb.conf"
readonly SEPARATOR="__SAMBA_SHARE_SEPARATOR__"
readonly WHITE_SPACE=" "
declare allow_hosts
declare compatibility_mode
declare delete_veto_files
declare name
declare password
declare username
declare veto_files
declare mounts

# Workgroup and interface
sed -i "s|%%WORKGROUP%%|$(bashio::config 'workgroup')|g" "${CONF}"
sed -i "s|%%INTERFACE%%|$(bashio::config 'interface')|g" "${CONF}"

mounts=$(bashio::config 'mounts')
bashio::log.info $mounts
# Remove possible white spaces from mount name
mounts=$(echo ${mounts//$WHITE_SPACE/$SEPARATOR})

# Create "home" group
addgroup "home"

# Veto files
veto_files=""
delete_veto_files="no"
if bashio::config.has_value 'veto_files'; then
    veto_files=$(bashio::config "veto_files | join(\"/\")")
    veto_files="/${veto_files}/"
    delete_veto_files="yes"
fi
sed -i "s|%%VETO_FILES%%|${veto_files}|g" "${CONF}"
sed -i "s|%%DELETE_VETO_FILES%%|${delete_veto_files}|g" "${CONF}"

# Read hostname from API or setting default "hassio"
name=$(bashio::config "hostname")
if bashio::var.is_empty "${name}"; then
    bashio::log.warning "Name not set, trying to use hostname."
    name=$(bashio::info.hostname)
fi
if bashio::var.is_empty "${name}"; then
    bashio::log.warning "Can't read hostname, using default."
    name="hassio"
fi
bashio::log.info "Hostname: ${name}"
sed -i "s|%%NAME%%|${name}|g" "${CONF}"

# Allowed hosts
allow_hosts=$(bashio::config "allow_hosts | join(\" \")")
sed -i "s#%%ALLOW_HOSTS%%#${allow_hosts}#g" "${CONF}"

# Init users
for login in $(bashio::config 'logins'); do
    bashio::log.info "Starting configuration of $login."

    username=$(echo ${login} | jq -r '.username')
    password=$(echo ${login} | jq -r '.password')

    bashio::log.info "Creating user $username."
    echo -e "${password}\n${password}" | adduser -H -G "home" -s /bin/false "${username}"

    bashio::log.info "Settings password for user $username."
    echo -e "${password}\n${password}" | smbpasswd -a -s -c "${CONF}" "${username}"
done

for mount_point in $mounts; do
    # revert whitespace changes for this mount point
    mount_point=$(echo ${mount_point//$SEPARATOR/$WHITE_SPACE})
    bashio::log.info "Starting configuration of $mount_point."

    disk_label=$(echo ${mount_point} | jq -r '.disk_label')
    backup=$(echo ${mount_point} | jq -r '.backup')
    mount_name=$(echo ${mount_point} | jq -r '.name')

    users_length=$(echo ${mount_point} | jq -r '.users' | jq length)
    valid_users='@home'

    if [ "$users_length" -gt "0" ]; then
      valid_users=$(echo ${mount_point} | jq -r '.users | join(" ")')
    fi
    bashio::log.info "Using users '$valid_users' for disk $disk_label."

    folder="/share/${disk_label}"
    disk="/dev/disk/by-label/${disk_label}"

    if [[ ! -e $folder ]]; then
        bashio::log.info "Creating folder $folder."
        mkdir -p $folder
    fi

    if [[ -e "$disk" ]]; then
        bashio::log.info "Mounting device $disk on target folder $folder."
        mount $disk $folder
        chown -R root:home $folder
    fi

    if bashio::var.true "$backup"; then
        bashio::log.info "Seting disk $disk_label as a backup disk."

        echo "[${mount_name}]" >> $CONF
        echo "   path = ${folder}" >> $CONF
        echo "   browseable = yes" >> $CONF
        echo "   writeable = yes" >> $CONF
        echo "   create mask = 0600" >> $CONF
        echo "   directory mask = 0700" >> $CONF
        echo "   vfs objects = catia fruit streams_xattr" >> $CONF
        echo "   fruit:time machine = yes" >> $CONF
        echo "   valid users = ${valid_users}" >> $CONF
        echo "   veto files = ${veto_files}" >> $CONF
        echo "   delete veto files = ${delete_veto_files}" >> $CONF
        echo "" >> $CONF
    else
        bashio::log.info "Seting disk $disk_label as a regular share."

        echo "[${mount_name}]" >> $CONF
        echo "   path = ${folder}" >> $CONF
        echo "   browseable = yes" >> $CONF
        echo "   writeable = yes" >> $CONF
        echo "   create mask = 0665" >> $CONF
        echo "   force create mode = 0665" >> $CONF
        echo "   directory mask = 02775" >> $CONF
        echo "   force directory mode = 02775" >> $CONF
        echo "   valid users = ${valid_users}" >> $CONF
        echo "   veto files = ${veto_files}" >> $CONF
        echo "   delete veto files = ${delete_veto_files}" >> $CONF
        echo "" >> $CONF
    fi
done
