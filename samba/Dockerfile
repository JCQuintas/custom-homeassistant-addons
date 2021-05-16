ARG BUILD_FROM
FROM $BUILD_FROM

# Add env
ENV LANG C.UTF-8

# Setup base
RUN apk --update add --no-cache samba-common-tools samba-server
RUN mkdir -p /var/lib/samba
RUN touch /etc/samba/lmhosts
RUN touch /var/lib/samba/account_policy.tdb
RUN touch /var/lib/samba/registry.tdb
RUN touch /var/lib/samba/winbindd_idmap.tdb

# Copy data
COPY rootfs /
