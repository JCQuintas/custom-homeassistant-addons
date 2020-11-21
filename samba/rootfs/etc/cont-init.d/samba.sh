#!/usr/bin/with-contenv bashio
# ==============================================================================
# Prepare the Samba service for running
# ==============================================================================
set -e

readonly CONF="/etc/samba/smb.conf"
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

for mountPoint in $mounts; do
    device=$(echo ${mountPoint} | jq -r '.device')
    target=$(echo ${mountPoint} | jq -r '.target')

    if [[ ! -e $target ]]; then
        bashio::log.info "Creating folder $target."
        mkdir -p $target
        chmod -R 02775 $target
    fi

    if [[ -e "$device" ]]; then
        bashio::log.info "Mounting device $device on target folder $target."
        mount $device $target
    fi
done

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
    username=$(echo ${login} | jq -r '.username')
    password=$(echo ${login} | jq -r '.password')
    bashio::log.info "Creating user $username."

    addgroup "${username}"
    adduser -D -H -G "${username}" -s /bin/false "${username}"

    bashio::log.info "Settings password for user $username."
    echo -e "${password}\n${password}" | smbpasswd -a -s -c "${CONF}" "${username}"
done