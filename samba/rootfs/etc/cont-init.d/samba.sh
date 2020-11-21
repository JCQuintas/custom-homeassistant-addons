#!/usr/bin/with-contenv bashio
# ==============================================================================
# Prepare the Samba service for running
# ==============================================================================
readonly CONF="/etc/samba/smb.conf"
declare allow_hosts
declare compatibility_mode
declare delete_veto_files
declare name
declare password
declare username
declare veto_files

# Check Login data
if ! bashio::config.has_value 'username' || ! bashio::config.has_value 'password'; then
    bashio::exit.nok "Setting a username and password is required!"
fi

# Workgroup and interface
sed -i "s|%%WORKGROUP%%|$(bashio::config 'workgroup')|g" "${CONF}"
sed -i "s|%%INTERFACE%%|$(bashio::config 'interface')|g" "${CONF}"

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
name=$(bashio::info.hostname)
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
for login in $(bashio::config 'logins[]'); do
    username=$(echo ${login} | jq -r '.username')
    password=$(echo ${login} | jq -r '.password')

    addgroup "${username}"
    adduser -D -H -G "${username}" -s /bin/false "${username}"

    echo -e "${password}\n${password}" \
        | smbpasswd -a -s -c "${CONF}" "${username}"
done