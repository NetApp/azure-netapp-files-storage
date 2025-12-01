#!/bin/bash

# Minimal PostgreSQL setup script for testing
set -e

echo "Starting PostgreSQL setup script at $(date)" | tee /var/log/postgresql-setup.log

# Variables from Terraform
POSTGRESQL_VERSION="${postgresql_version}"
NETAPP_IP="${volume_ip}"
MOUNT_PATH="/mnt/${volume_name}"

echo "Configuration:" | tee -a /var/log/postgresql-setup.log
echo "PostgreSQL Version: $POSTGRESQL_VERSION" | tee -a /var/log/postgresql-setup.log
echo "NetApp IP: $NETAPP_IP" | tee -a /var/log/postgresql-setup.log
echo "Mount Path: $MOUNT_PATH" | tee -a /var/log/postgresql-setup.log

# Update system
export DEBIAN_FRONTEND=noninteractive
apt-get update | tee -a /var/log/postgresql-setup.log 2>&1

# Install NFS client
echo "Installing NFS client..." | tee -a /var/log/postgresql-setup.log
apt-get install -y nfs-common | tee -a /var/log/postgresql-setup.log 2>&1

# Create mount directory
mkdir -p "$MOUNT_PATH"

# Test NetApp connectivity
echo "Testing NetApp connectivity..." | tee -a /var/log/postgresql-setup.log
if ping -c 3 "$NETAPP_IP" | tee -a /var/log/postgresql-setup.log 2>&1; then
    echo "NetApp endpoint is reachable" | tee -a /var/log/postgresql-setup.log
else
    echo "ERROR: NetApp endpoint not reachable" | tee -a /var/log/postgresql-setup.log
    exit 1
fi

# Mount NetApp volume
echo "Mounting NetApp volume..." | tee -a /var/log/postgresql-setup.log
if mount -t nfs -o rw,hard,rsize=262144,wsize=262144,vers=3,tcp "$NETAPP_IP:/${volume_name}" "$MOUNT_PATH" | tee -a /var/log/postgresql-setup.log 2>&1; then
    echo "NetApp volume mounted successfully" | tee -a /var/log/postgresql-setup.log
    
    # Verify mount
    if mountpoint -q "$MOUNT_PATH"; then
        echo "Mount verified successfully" | tee -a /var/log/postgresql-setup.log
        ls -la "$MOUNT_PATH" | tee -a /var/log/postgresql-setup.log
    else
        echo "ERROR: Mount verification failed" | tee -a /var/log/postgresql-setup.log
        exit 1
    fi
else
    echo "ERROR: Mount failed" | tee -a /var/log/postgresql-setup.log
    exit 1
fi

# Add to fstab
echo "Adding mount to fstab..." | tee -a /var/log/postgresql-setup.log
echo "$NETAPP_IP:/${volume_name} $MOUNT_PATH nfs rw,hard,rsize=262144,wsize=262144,vers=3,tcp 0 0" >> /etc/fstab

# Install PostgreSQL
echo "Installing PostgreSQL..." | tee -a /var/log/postgresql-setup.log
apt-get install -y wget ca-certificates | tee -a /var/log/postgresql-setup.log 2>&1

wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - 2>&1 | tee -a /var/log/postgresql-setup.log
echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

apt-get update | tee -a /var/log/postgresql-setup.log 2>&1
apt-get install -y "postgresql-$POSTGRESQL_VERSION" "postgresql-contrib-$POSTGRESQL_VERSION" | tee -a /var/log/postgresql-setup.log 2>&1

echo "PostgreSQL installation completed successfully" | tee -a /var/log/postgresql-setup.log

# Configure PostgreSQL with NetApp volume
DATA_DIR="$MOUNT_PATH/postgresql-data"
mkdir -p "$DATA_DIR"
chown -R postgres:postgres "$MOUNT_PATH"
chmod 700 "$DATA_DIR"

# Stop any default PostgreSQL service and clean up lock files
systemctl stop postgresql 2>/dev/null || true
pkill -f postgres 2>/dev/null || true
rm -f /var/run/postgresql/.s.PGSQL.${postgresql_port}.lock 2>/dev/null || true
sleep 3

# Initialize database on NetApp volume
echo "Initializing PostgreSQL on NetApp volume..." | tee -a /var/log/postgresql-setup.log
sudo -u postgres "/usr/lib/postgresql/$POSTGRESQL_VERSION/bin/initdb" -D "$DATA_DIR" -E UTF8 --locale=C.UTF-8 | tee -a /var/log/postgresql-setup.log 2>&1

# Configure PostgreSQL
echo "listen_addresses = '*'" >> "$DATA_DIR/postgresql.conf"
echo "port = ${postgresql_port}" >> "$DATA_DIR/postgresql.conf"
echo "host all all 0.0.0.0/0 md5" >> "$DATA_DIR/pg_hba.conf"

# Start PostgreSQL
echo "Starting PostgreSQL..." | tee -a /var/log/postgresql-setup.log
sudo -u postgres "/usr/lib/postgresql/$POSTGRESQL_VERSION/bin/pg_ctl" -D "$DATA_DIR" -l "$DATA_DIR/postgres.log" -w start | tee -a /var/log/postgresql-setup.log 2>&1

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..." | tee -a /var/log/postgresql-setup.log
for i in {1..30}; do
    if sudo -u postgres "/usr/lib/postgresql/$POSTGRESQL_VERSION/bin/pg_isready" -p "${postgresql_port}" -q; then
        echo "PostgreSQL is ready!" | tee -a /var/log/postgresql-setup.log
        break
    fi
    echo "Attempt $i/30 - waiting for PostgreSQL..." | tee -a /var/log/postgresql-setup.log
    sleep 2
done

# Configure database
echo "Configuring database..." | tee -a /var/log/postgresql-setup.log
sudo -u postgres psql -p "${postgresql_port}" -c "ALTER USER postgres PASSWORD '${postgresql_admin_password}';" | tee -a /var/log/postgresql-setup.log 2>&1
sudo -u postgres psql -p "${postgresql_port}" -c "CREATE DATABASE ${database_name};" | tee -a /var/log/postgresql-setup.log 2>&1
sudo -u postgres psql -p "${postgresql_port}" -c "CREATE USER ${database_user} WITH PASSWORD '${database_password}';" | tee -a /var/log/postgresql-setup.log 2>&1
sudo -u postgres psql -p "${postgresql_port}" -c "GRANT ALL PRIVILEGES ON DATABASE ${database_name} TO ${database_user};" | tee -a /var/log/postgresql-setup.log 2>&1

# Connect to the database and grant schema permissions
echo "Setting up database schema permissions..." | tee -a /var/log/postgresql-setup.log
sudo -u postgres psql -p "${postgresql_port}" -d "${database_name}" -c "GRANT ALL ON SCHEMA public TO ${database_user};" | tee -a /var/log/postgresql-setup.log 2>&1
sudo -u postgres psql -p "${postgresql_port}" -d "${database_name}" -c "GRANT CREATE ON SCHEMA public TO ${database_user};" | tee -a /var/log/postgresql-setup.log 2>&1

# Test the setup with a simple table creation and insertion
echo "Testing database setup..." | tee -a /var/log/postgresql-setup.log
sudo -u postgres psql -p "${postgresql_port}" -d "${database_name}" -c "CREATE TABLE test_setup (id INT, message TEXT);" | tee -a /var/log/postgresql-setup.log 2>&1
sudo -u postgres psql -p "${postgresql_port}" -d "${database_name}" -c "INSERT INTO test_setup VALUES (1, 'PostgreSQL setup completed automatically!');" | tee -a /var/log/postgresql-setup.log 2>&1
sudo -u postgres psql -p "${postgresql_port}" -d "${database_name}" -c "SELECT * FROM test_setup;" | tee -a /var/log/postgresql-setup.log 2>&1
sudo -u postgres psql -p "${postgresql_port}" -d "${database_name}" -c "DROP TABLE test_setup;" | tee -a /var/log/postgresql-setup.log 2>&1

echo "PostgreSQL setup completed successfully at $(date)" | tee -a /var/log/postgresql-setup.log
echo "Data directory: $DATA_DIR" | tee -a /var/log/postgresql-setup.log
echo "Log file: /var/log/postgresql-setup.log" | tee -a /var/log/postgresql-setup.log
