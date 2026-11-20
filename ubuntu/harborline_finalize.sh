#!/usr/bin/env bash
# =============================================================================
# Harborline - FINALIZE before giving the VM to players
#
#   sudo bash harborline_finalize.sh
#
# Run ONLY after: flags copied to Kali, CTFd loaded, full test-solve done,
# and a VM snapshot taken (so you can still get back in later).
#
# Removes YOUR install account (it has sudo = an unintended path to root),
# deletes the flags files and build traces, then powers off.
# After this you cannot log in to this VM anymore. That is intended.
# =============================================================================
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo: sudo bash $0"; exit 1; }

BUILDER="$(cat /root/.harborline_builder 2>/dev/null || echo "${SUDO_USER:-}")"
[ -n "$BUILDER" ] && [ "$BUILDER" != "root" ] || { echo "Cannot tell which account to remove."; exit 1; }

echo "This will:"
echo "  - remove sudo and lock + delete the account '${BUILDER}'"
echo "  - delete the flags files on this VM"
echo "  - clear logs and histories, then power off"
echo
read -r -p "Did you copy harborline_flags.json to Kali AND take a snapshot? Type YES: " ans
[ "$ans" = "YES" ] || { echo "Aborted."; exit 1; }

echo "[finalize] Checking for other accounts that could bypass the scenario"
awk -F: '$3>=1000 && $3<65534 {print $1}' /etc/passwd | while read -r u; do
  case "$u" in ohaddad|snabil|"$BUILDER") ;; *) echo "  [!] Unexpected account: $u (review manually)";; esac
done

echo "[finalize] Removing build account access"
gpasswd -d "$BUILDER" sudo  >/dev/null 2>&1 || true
gpasswd -d "$BUILDER" adm   >/dev/null 2>&1 || true
gpasswd -d "$BUILDER" lxd   >/dev/null 2>&1 || true
rm -f "/etc/sudoers.d/${BUILDER}" /etc/sudoers.d/90-cloud-init-users
rm -rf "/home/${BUILDER}/.ssh"
usermod -L -s /usr/sbin/nologin "$BUILDER"

# The account is in use right now, so delete it on the next boot
cat > /etc/systemd/system/harborline-firstboot.service <<UNIT
[Unit]
Description=Harborline one-time cleanup
After=multi-user.target
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'userdel -r ${BUILDER} 2>/dev/null; rm -f /root/.harborline_builder; systemctl disable harborline-firstboot.service; rm -f /etc/systemd/system/harborline-firstboot.service'
[Install]
WantedBy=multi-user.target
UNIT
systemctl enable harborline-firstboot.service >/dev/null 2>&1

echo "[finalize] Deleting flags files and build traces"
rm -f /root/harborline_flags.json "/home/${BUILDER}/harborline_flags.json" \
      /root/suid_audit.txt "/home/${BUILDER}"/harborline_*.sh
for h in /root /home/*; do
  rm -f "$h/.bash_history" "$h/.mysql_history" "$h/.lesshst" "$h/.viminfo" "$h/.sudo_as_admin_successful"
done
rm -rf /var/www/html/portal/uploads/* /opt/backup/archives/*
mysql -e "TRUNCATE harborline.manifests;" 2>/dev/null || true
find /var/log -type f -exec truncate -s 0 {} \;
journalctl --rotate >/dev/null 2>&1 && journalctl --vacuum-time=1s >/dev/null 2>&1 || true
rm -rf /tmp/* /var/tmp/*
apt-get clean
history -c 2>/dev/null || true

echo "[finalize] Done. Powering off in 5 seconds."
echo "Next in your hypervisor: set the network to the lab-only mode you ship with,"
echo "then export the VM (VMware: File > Export to OVF; VirtualBox: Export Appliance)."
sync
sleep 5
poweroff
