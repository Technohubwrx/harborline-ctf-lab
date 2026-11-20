#!/usr/bin/env bash
# =============================================================================
# Harborline boot2root - ALL-IN-ONE SETUP (run inside the Ubuntu VM)
#
#   sudo bash harborline_setup.sh
#
# Updates the system, then installs and configures users, services, the
# vulnerable staff portal, the privilege-escalation path and six random flags.
# Flags are saved to:
#   /root/harborline_flags.json            (root copy)
#   /home/<your user>/harborline_flags.json (copy you can scp to Kali)
# Re-running regenerates ALL flags: reload CTFd afterwards.
#
# Target: Ubuntu Server 24.04 LTS. FOR ISOLATED LAB NETWORKS ONLY.
# =============================================================================
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

[ "$(id -u)" -eq 0 ] || { echo "Run with sudo: sudo bash $0"; exit 1; }

BUILDER="${SUDO_USER:-}"
if [ -z "$BUILDER" ] || [ "$BUILDER" = "root" ]; then
  echo "Run this from your normal Ubuntu account using sudo (not as root directly)."
  exit 1
fi

. /etc/os-release
if [ "${VERSION_ID:-}" != "24.04" ]; then
  echo "[!] Warning: tested on Ubuntu 24.04, this is ${PRETTY_NAME}. Continuing in 5s..."
  sleep 5
fi

log() { echo -e "\n\e[1;34m[harborline]\e[0m $*"; }
rand_hex() { openssl rand -hex "${1:-8}"; }

# -----------------------------------------------------------------------------
# 0. Scenario secrets (new on every run)
# -----------------------------------------------------------------------------
FLAG1="HARBOR{lighthouse_$(rand_hex)}"
FLAG2="HARBOR{welcome_aboard_$(rand_hex)}"
FLAG3="HARBOR{manifest_desk_$(rand_hex)}"
FLAG4="HARBOR{cargo_hold_$(rand_hex)}"
FLAG5="HARBOR{crew_quarters_$(rand_hex)}"
FLAG6="HARBOR{captains_log_$(rand_hex)}"

LINA_PORTAL_PASS='Harborline2023!'     # default-pattern password (intended)
OMAR_PASS='0mar_Dispatch#88'            # reused for DB + Linux (intended)
SARA_PASS="$(rand_hex 24)"              # strong, not a target
SARA_PORTAL_PASS="$(rand_hex 16)"       # strong, not a target
ROOT_PASS="$(rand_hex 24)"              # strong, not a target

# -----------------------------------------------------------------------------
# 1. Update and install packages
# -----------------------------------------------------------------------------
log "Updating the system (fully patched: no kernel shortcuts)"
apt-get update -y
apt-get full-upgrade -y
log "Installing packages"
apt-get install -y openssh-server apache2 libapache2-mod-php php-mysql php-cli \
                   mariadb-server vsftpd cron openssl enscript ghostscript

hostnamectl set-hostname harborline
sed -i '/127.0.1.1/d' /etc/hosts && echo "127.0.1.1 harborline" >> /etc/hosts
echo "root:${ROOT_PASS}" | chpasswd
echo "$BUILDER" > /root/.harborline_builder   # used by finalize to remove your access

# -----------------------------------------------------------------------------
# 2. Users and groups
# -----------------------------------------------------------------------------
log "Creating users and groups"
getent group ops >/dev/null || groupadd ops
id ohaddad &>/dev/null || useradd -m -s /bin/bash -G ops ohaddad
id snabil  &>/dev/null || useradd -m -s /bin/bash -G sudo snabil
echo "ohaddad:${OMAR_PASS}" | chpasswd
echo "snabil:${SARA_PASS}"  | chpasswd
chmod 750 /home/ohaddad /home/snabil "/home/${BUILDER}"

# -----------------------------------------------------------------------------
# 3. SSH (00- prefix wins over cloud-init's 50- file: first match wins)
# -----------------------------------------------------------------------------
log "Configuring SSH"
cat > /etc/ssh/sshd_config.d/00-harborline.conf <<'EOF'
PasswordAuthentication yes
PermitRootLogin no
EOF
systemctl enable ssh >/dev/null 2>&1 || true
systemctl restart ssh

# -----------------------------------------------------------------------------
# 4. Anonymous FTP with onboarding pack + flag 2
# -----------------------------------------------------------------------------
log "Configuring anonymous FTP"
mkdir -p /srv/ftp/pub /var/run/vsftpd/empty
cat > /etc/vsftpd.conf <<'EOF'
listen=YES
listen_ipv6=NO
anonymous_enable=YES
local_enable=NO
write_enable=NO
anon_upload_enable=NO
anon_mkdir_write_enable=NO
anon_root=/srv/ftp
no_anon_password=YES
hide_ids=YES
ftpd_banner=Harborline Freight - staff file share
secure_chroot_dir=/var/run/vsftpd/empty
pasv_min_port=40000
pasv_max_port=40010
EOF

cat > /tmp/onboarding.txt <<'EOF'
HARBORLINE FREIGHT
Staff Onboarding Pack - v2.1
Prepared by: Lina Mostafa, Operations Manager

Welcome aboard!

1. YOUR ACCOUNTS
   Your username is your first initial followed by your surname,
   all lowercase. Example: John Smith -> jsmith

   Your first password is the company name, then the year you
   joined, then an exclamation mark. Example: Harborline2019!

   Please change it the first time you log in to the staff portal.

2. STAFF PORTAL
   Dispatch and operations staff use the portal to upload
   shipment manifests. Ask Omar in development if you have trouble.

3. IT SUPPORT
   For anything else, contact Sara in IT.

Fair winds,
Lina
EOF
enscript -q -B -f Courier11 -o - /tmp/onboarding.txt | ps2pdf - /srv/ftp/pub/onboarding.pdf
rm -f /tmp/onboarding.txt
echo "${FLAG2}" > /srv/ftp/pub/flag.txt
chown -R root:root /srv/ftp
chmod 755 /srv/ftp /srv/ftp/pub
chmod 644 /srv/ftp/pub/*
systemctl enable vsftpd >/dev/null
systemctl restart vsftpd

# -----------------------------------------------------------------------------
# 5. Database (localhost only)
# -----------------------------------------------------------------------------
log "Configuring MariaDB"
systemctl enable --now mariadb
hash_pw() { php -r 'echo password_hash($argv[1], PASSWORD_DEFAULT);' "$1"; }
LINA_HASH=$(hash_pw "${LINA_PORTAL_PASS}")
OMAR_HASH=$(hash_pw "$(rand_hex 16)")
SARA_HASH=$(hash_pw "${SARA_PORTAL_PASS}")

mysql <<EOF
CREATE DATABASE IF NOT EXISTS harborline;
CREATE USER IF NOT EXISTS 'ohaddad'@'localhost' IDENTIFIED BY '${OMAR_PASS}';
ALTER USER 'ohaddad'@'localhost' IDENTIFIED BY '${OMAR_PASS}';
GRANT SELECT, INSERT, UPDATE ON harborline.* TO 'ohaddad'@'localhost';
FLUSH PRIVILEGES;
USE harborline;
DROP TABLE IF EXISTS users;
CREATE TABLE users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(32) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  full_name VARCHAR(64) NOT NULL,
  role VARCHAR(32) NOT NULL
);
INSERT INTO users (username, password_hash, full_name, role) VALUES
  ('lmostafa', '${LINA_HASH}', 'Lina Mostafa', 'Operations'),
  ('ohaddad',  '${OMAR_HASH}', 'Omar Haddad',  'Developer'),
  ('snabil',   '${SARA_HASH}', 'Sara Nabil',   'IT Admin');
DROP TABLE IF EXISTS manifests;
CREATE TABLE manifests (
  id INT AUTO_INCREMENT PRIMARY KEY,
  uploaded_by VARCHAR(32) NOT NULL,
  filename VARCHAR(255) NOT NULL,
  uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF

# -----------------------------------------------------------------------------
# 6. Public website
# -----------------------------------------------------------------------------
log "Deploying the public website"
WEB=/var/www/html
rm -rf "${WEB:?}"/*
mkdir -p "$WEB/portal/uploads"

cat > "$WEB/style.css" <<'EOF'
body{font-family:Arial,Helvetica,sans-serif;margin:0;background:#f4f6f8;color:#1d2b36}
header{background:#0b3c5d;color:#fff;padding:18px 32px}
header a{color:#cfe3f2;margin-right:18px;text-decoration:none}
main{max-width:860px;margin:32px auto;background:#fff;padding:28px 36px;border-radius:6px}
footer{text-align:center;color:#6b7c88;font-size:13px;padding:24px}
.card{border:1px solid #dde4ea;border-radius:6px;padding:14px 18px;margin:12px 0}
input,button{padding:8px;margin:4px 0;font-size:14px}
.err{color:#b00020}.ok{color:#1b7f3b}
EOF

cat > "$WEB/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Harborline Freight</title><link rel="stylesheet" href="/style.css"></head>
<body>
<header><strong>Harborline Freight</strong> &nbsp; <a href="/">Home</a><a href="/about.html">About us</a></header>
<main>
  <h1>Reliable shipping, port to port</h1>
  <p>Harborline Freight moves containers between regional ports with real-time tracking
     and a dedicated dispatch team.</p>
  <div class="card"><h3>Track a shipment</h3><p>Online tracking is coming soon. Call dispatch for updates.</p></div>
</main>
<footer>&copy; Harborline Freight. All rights reserved.
<!-- TODO(ohaddad): remove before go-live. Staff portal QA token: __FLAG1__ -->
</footer>
</body>
</html>
EOF

cat > "$WEB/about.html" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>About - Harborline Freight</title><link rel="stylesheet" href="/style.css"></head>
<body>
<header><strong>Harborline Freight</strong> &nbsp; <a href="/">Home</a><a href="/about.html">About us</a></header>
<main>
  <h1>Meet the crew</h1>
  <div class="card"><h3>Lina Mostafa</h3><p>Operations Manager. Lina joined us in 2023 and keeps the fleet moving.</p></div>
  <div class="card"><h3>Omar Haddad</h3><p>Software Developer since 2024. Omar built our new staff portal.</p></div>
  <div class="card"><h3>Sara Nabil</h3><p>IT Administrator. With Harborline since 2019.</p></div>
</main>
<footer>&copy; Harborline Freight. All rights reserved.</footer>
</body>
</html>
EOF

cat > "$WEB/robots.txt" <<'EOF'
User-agent: *
Disallow: /portal/
EOF

# -----------------------------------------------------------------------------
# 7. Staff portal (PHP)
# -----------------------------------------------------------------------------
log "Deploying the staff portal"
P="$WEB/portal"

cat > "$P/config.php" <<'EOF'
<?php
// Harborline staff portal - configuration
// TODO: move these to environment variables before go-live (Omar)
define('DB_HOST', '127.0.0.1');
define('DB_NAME', 'harborline');
define('DB_USER', 'ohaddad');
define('DB_PASS', '__DB_PASS__');

session_start();

function db() {
    static $pdo = null;
    if ($pdo === null) {
        $pdo = new PDO('mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4',
                       DB_USER, DB_PASS,
                       [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
    }
    return $pdo;
}

function require_login() {
    if (empty($_SESSION['user'])) {
        header('Location: /portal/index.php');
        exit;
    }
}

function h($s) { return htmlspecialchars($s, ENT_QUOTES, 'UTF-8'); }
EOF

cat > "$P/index.php" <<'EOF'
<?php
require __DIR__ . '/config.php';

$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = trim($_POST['username'] ?? '');
    $password = $_POST['password'] ?? '';
    $stmt = db()->prepare('SELECT username, password_hash, full_name FROM users WHERE username = ?');
    $stmt->execute([$username]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($row && password_verify($password, $row['password_hash'])) {
        session_regenerate_id(true);
        $_SESSION['user'] = $row['username'];
        $_SESSION['name'] = $row['full_name'];
        header('Location: /portal/dashboard.php');
        exit;
    }
    $error = 'Invalid username or password.';
}
?>
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Staff Portal - Harborline</title><link rel="stylesheet" href="/style.css"></head>
<body>
<header><strong>Harborline Staff Portal</strong></header>
<main>
  <h2>Staff sign-in</h2>
  <?php if ($error): ?><p class="err"><?= h($error) ?></p><?php endif; ?>
  <form method="post">
    <label>Username<br><input name="username" autocomplete="off"></label><br>
    <label>Password<br><input name="password" type="password"></label><br>
    <button type="submit">Sign in</button>
  </form>
  <p style="font-size:13px;color:#6b7c88">New staff: see your onboarding pack for first-login details.</p>
</main>
</body>
</html>
EOF

cat > "$P/dashboard.php" <<'EOF'
<?php
require __DIR__ . '/config.php';
require_login();

$stmt = db()->prepare('SELECT filename, uploaded_at FROM manifests WHERE uploaded_by = ? ORDER BY id DESC LIMIT 10');
$stmt->execute([$_SESSION['user']]);
$manifests = $stmt->fetchAll(PDO::FETCH_ASSOC);
?>
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Dashboard - Harborline</title><link rel="stylesheet" href="/style.css"></head>
<body>
<header><strong>Harborline Staff Portal</strong> &nbsp;
  <a href="/portal/dashboard.php">Dashboard</a><a href="/portal/upload.php">Upload manifest</a><a href="/portal/logout.php">Sign out</a></header>
<main>
  <h2>Welcome, <?= h($_SESSION['name']) ?></h2>
  <div class="card"><strong>Notice:</strong> Your account still uses its first-login password. Please change it.
    <br><small>Security audit reference: __FLAG3__</small></div>
  <h3>Your recent manifests</h3>
  <?php if (!$manifests): ?><p>No manifests uploaded yet.</p><?php endif; ?>
  <ul>
  <?php foreach ($manifests as $m): ?>
    <li><a href="/portal/uploads/<?= rawurlencode($m['filename']) ?>"><?= h($m['filename']) ?></a>
        <small>(<?= h($m['uploaded_at']) ?>)</small></li>
  <?php endforeach; ?>
  </ul>
</main>
</body>
</html>
EOF

cat > "$P/upload.php" <<'EOF'
<?php
require __DIR__ . '/config.php';
require_login();

$message = '';
$ok = false;

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_FILES['manifest'])) {
    $file = $_FILES['manifest'];
    $name = basename($file['name']);
    $ext  = strtolower(pathinfo($name, PATHINFO_EXTENSION));

    // Block dangerous file types
    $blocked = ['php', 'exe', 'sh'];

    if ($file['error'] !== UPLOAD_ERR_OK) {
        $message = 'Upload failed.';
    } elseif ($file['size'] > 2 * 1024 * 1024) {
        $message = 'File too large (2 MB max).';
    } elseif ($name === '' || in_array($ext, $blocked, true)) {
        $message = 'That file type is not allowed.';
    } elseif (move_uploaded_file($file['tmp_name'], __DIR__ . '/uploads/' . $name)) {
        $stmt = db()->prepare('INSERT INTO manifests (uploaded_by, filename) VALUES (?, ?)');
        $stmt->execute([$_SESSION['user'], $name]);
        $message = 'Manifest uploaded.';
        $ok = true;
    } else {
        $message = 'Could not save the file.';
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Upload - Harborline</title><link rel="stylesheet" href="/style.css"></head>
<body>
<header><strong>Harborline Staff Portal</strong> &nbsp;
  <a href="/portal/dashboard.php">Dashboard</a><a href="/portal/upload.php">Upload manifest</a><a href="/portal/logout.php">Sign out</a></header>
<main>
  <h2>Upload a shipment manifest</h2>
  <?php if ($message): ?><p class="<?= $ok ? 'ok' : 'err' ?>"><?= h($message) ?></p><?php endif; ?>
  <form method="post" enctype="multipart/form-data">
    <input type="file" name="manifest"><br>
    <button type="submit">Upload</button>
  </form>
  <p style="font-size:13px;color:#6b7c88">Accepted: PDF, CSV, XLSX. Uploaded files are listed on your dashboard.</p>
</main>
</body>
</html>
EOF

cat > "$P/logout.php" <<'EOF'
<?php
require __DIR__ . '/config.php';
session_destroy();
header('Location: /portal/index.php');
EOF

# Insert build-specific values
sed -i "s|__FLAG1__|${FLAG1}|"     "$WEB/index.html"
sed -i "s|__FLAG3__|${FLAG3}|"     "$P/dashboard.php"
sed -i "s|__DB_PASS__|${OMAR_PASS}|" "$P/config.php"

# Permissions: Apache (www-data) reads everything, writes only to uploads
chown -R root:www-data "$WEB"
find "$WEB" -type d -exec chmod 750 {} \;
find "$WEB" -type f -exec chmod 640 {} \;
chown www-data:www-data "$P/uploads"
chmod 750 "$P/uploads"

# Flag 4: readable once a shell as www-data is obtained
echo "${FLAG4}" > /var/www/flag_cargo_hold.txt
chown www-data:www-data /var/www/flag_cargo_hold.txt
chmod 400 /var/www/flag_cargo_hold.txt

# Apache: hide version, no directory listings
sed -i 's/^ServerTokens .*/ServerTokens Prod/; s/^ServerSignature .*/ServerSignature Off/' \
  /etc/apache2/conf-available/security.conf
cat > /etc/apache2/conf-available/harborline.conf <<'EOF'
<Directory /var/www/html>
    Options -Indexes
    AllowOverride None
</Directory>
EOF
a2enconf harborline >/dev/null
systemctl enable apache2 >/dev/null
systemctl restart apache2

# -----------------------------------------------------------------------------
# 8. User and root flags
# -----------------------------------------------------------------------------
log "Placing user and root flags"
echo "${FLAG5}" > /home/ohaddad/user.txt
chown ohaddad:ohaddad /home/ohaddad/user.txt
chmod 600 /home/ohaddad/user.txt
echo "${FLAG6}" > /root/root.txt
chmod 600 /root/root.txt

# -----------------------------------------------------------------------------
# 9. Privilege escalation: root cron runs an ops-writable script (intended)
# -----------------------------------------------------------------------------
log "Configuring the backup job"
mkdir -p /opt/backup/archives
cat > /opt/backup/nightly.sh <<'EOF'
#!/bin/bash
# Harborline nightly backup - maintained by Sara Nabil (IT)
# Archives the staff portal so dispatch never loses uploaded manifests.
# NOTE: ops team may edit this script to add folders. -- Sara

STAMP=$(date +%Y%m%d-%H%M)
DEST=/opt/backup/archives

tar -czf "${DEST}/portal-${STAMP}.tar.gz" -C /var/www html 2>/dev/null

# keep only the 5 newest archives
ls -1t "${DEST}"/portal-*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm -f
EOF
chown root:root /opt/backup /opt/backup/archives
chmod 755 /opt/backup
chmod 700 /opt/backup/archives
chown root:ops /opt/backup/nightly.sh
chmod 775 /opt/backup/nightly.sh

cat > /etc/cron.d/harborline-backup <<'EOF'
# Harborline nightly backup (runs often so staff "never lose work")
*/2 * * * * root /opt/backup/nightly.sh >/dev/null 2>&1
EOF
chmod 644 /etc/cron.d/harborline-backup
systemctl enable --now cron >/dev/null

# -----------------------------------------------------------------------------
# 10. Clean up and save flags
# -----------------------------------------------------------------------------
log "Cleaning up build-only tools"
apt-get purge -y enscript ghostscript >/dev/null
apt-get autoremove -y >/dev/null
apt-get clean

log "Auditing SUID binaries -> /root/suid_audit.txt (compare with a stock install)"
find / -xdev -perm -4000 -type f 2>/dev/null | sort > /root/suid_audit.txt

FLAGS_JSON=$(cat <<EOF
{
  "Lighthouse":     "${FLAG1}",
  "Welcome Aboard": "${FLAG2}",
  "Manifest Desk":  "${FLAG3}",
  "Cargo Hold":     "${FLAG4}",
  "Crew Quarters":  "${FLAG5}",
  "Captain's Log":  "${FLAG6}"
}
EOF
)
echo "$FLAGS_JSON" > /root/harborline_flags.json
chmod 600 /root/harborline_flags.json
echo "$FLAGS_JSON" > "/home/${BUILDER}/harborline_flags.json"
chown "${BUILDER}:${BUILDER}" "/home/${BUILDER}/harborline_flags.json"
chmod 600 "/home/${BUILDER}/harborline_flags.json"

# -----------------------------------------------------------------------------
# 11. Self-check
# -----------------------------------------------------------------------------
log "Service check"
for s in ssh apache2 vsftpd mariadb cron; do
  printf "  %-8s %s\n" "$s" "$(systemctl is-active "$s")"
done

log "SETUP COMPLETE"
echo "  IP addresses of this VM:"
ip -4 -o addr show scope global | awk '{print "    " $2 ": " $4}'
echo
echo "  Flags saved to /home/${BUILDER}/harborline_flags.json"
echo "  Next, from Kali:  scp ${BUILDER}@<this-vm-ip>:harborline_flags.json ."
echo "  Then take a VM snapshot named 'clean' before test-solving."
