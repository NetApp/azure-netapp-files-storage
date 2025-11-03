#!/bin/bash

set -e

exec > /var/log/postgresql-setup.log 2>&1
echo "Starting PostgreSQL setup script at $(date)"

# Variables from template
POSTGRESQL_VERSION="${postgresql_version}"
POSTGRESQL_ADMIN_PASSWORD="${postgresql_admin_password}"
DATABASE_NAME="${database_name}"
DATABASE_USER="${database_user}"
DATABASE_PASSWORD="${database_password}"
NETAPP_IP="${volume_ip}"
NETAPP_PATH="/${volume_name}"
MOUNT_PATH="/mnt/${volume_name}"
POSTGRESQL_DATA_DIR="$MOUNT_PATH/postgresql-data"
POSTGRESQL_PORT="${postgresql_port}"

echo "PostgreSQL Version: $POSTGRESQL_VERSION"
echo "NetApp IP: $NETAPP_IP"
echo "NetApp Path: $NETAPP_PATH"
echo "Mount Path: $MOUNT_PATH"
echo "PostgreSQL Data Directory: $POSTGRESQL_DATA_DIR"

# Install NFS client
echo "Installing NFS client..."
apt-get update -q
apt-get install -y nfs-common

# Create mount directory
echo "Creating mount directory..."
mkdir -p $MOUNT_PATH

# Wait for NetApp endpoint to be reachable
echo "Checking if NetApp endpoint is reachable..."
RETRIES=30
count=0
while [ $count -lt $RETRIES ]; do
    if ping -c 1 $NETAPP_IP &> /dev/null; then
        echo "NetApp endpoint is reachable"
        break
    fi
    
    count=$((count+1))
    echo "Waiting for NetApp endpoint... Attempt $count of $RETRIES"
    sleep 10
done

if [ $count -eq $RETRIES ]; then
    echo "ERROR: Could not reach NetApp endpoint after $RETRIES attempts"
    exit 1
fi

# Mount the ANF volume
echo "Mounting ANF volume..."
mount -t nfs -o rw,hard,rsize=262144,wsize=262144,vers=3,tcp $NETAPP_IP:$NETAPP_PATH $MOUNT_PATH

# Verify mount
if ! mount | grep -q "$MOUNT_PATH"; then
    echo "ERROR: ANF volume mount failed"
    exit 1
fi

echo "ANF volume mounted successfully"

# Add to fstab for persistence
echo "Adding to fstab for persistence..."
grep -v "$MOUNT_PATH" /etc/fstab > /etc/fstab.new || true
mv /etc/fstab.new /etc/fstab
echo "$NETAPP_IP:$NETAPP_PATH $MOUNT_PATH nfs rw,hard,rsize=262144,wsize=262144,vers=3,tcp 0 0" >> /etc/fstab

# Install PostgreSQL
echo "Installing PostgreSQL $POSTGRESQL_VERSION..."
export DEBIAN_FRONTEND=noninteractive

# Add PostgreSQL APT repository
apt-get install -y wget ca-certificates
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list
apt-get update -q

# Install PostgreSQL
apt-get install -y postgresql-$POSTGRESQL_VERSION postgresql-contrib-$POSTGRESQL_VERSION

# Stop PostgreSQL service (we'll move data directory)
echo "Stopping PostgreSQL service..."
systemctl stop postgresql

# Create PostgreSQL data directory on ANF
echo "Creating PostgreSQL data directory on ANF..."
mkdir -p $POSTGRESQL_DATA_DIR
chown postgres:postgres $POSTGRESQL_DATA_DIR
chmod 700 $POSTGRESQL_DATA_DIR

# Move existing data directory to ANF (if it exists and is empty, initialize there)
if [ -d "/var/lib/postgresql/$POSTGRESQL_VERSION/main" ]; then
    echo "Moving PostgreSQL data directory to ANF..."
    # Copy data directory to ANF
    sudo -u postgres cp -a /var/lib/postgresql/$POSTGRESQL_VERSION/main/* $POSTGRESQL_DATA_DIR/ 2>/dev/null || true
fi

# Initialize PostgreSQL data directory on ANF if needed
if [ ! -f "$POSTGRESQL_DATA_DIR/PG_VERSION" ]; then
    echo "Initializing PostgreSQL data directory on ANF..."
    sudo -u postgres /usr/lib/postgresql/$POSTGRESQL_VERSION/bin/initdb -D $POSTGRESQL_DATA_DIR -E UTF8 --locale=en_US.UTF-8
fi

# Update PostgreSQL configuration
echo "Configuring PostgreSQL..."
POSTGRESQL_CONF="$POSTGRESQL_DATA_DIR/postgresql.conf"
POSTGRESQL_PG_HBA="$POSTGRESQL_DATA_DIR/pg_hba.conf"

# Update postgresql.conf
sed -i "s|#data_directory =.*|data_directory = '$POSTGRESQL_DATA_DIR'|" $POSTGRESQL_CONF || echo "data_directory = '$POSTGRESQL_DATA_DIR'" >> $POSTGRESQL_CONF
sed -i "s|#listen_addresses =.*|listen_addresses = '*'|" $POSTGRESQL_CONF || echo "listen_addresses = '*'" >> $POSTGRESQL_CONF
sed -i "s|#port =.*|port = $POSTGRESQL_PORT|" $POSTGRESQL_CONF || echo "port = $POSTGRESQL_PORT" >> $POSTGRESQL_CONF
sed -i "s|#logging_collector =.*|logging_collector = on|" $POSTGRESQL_CONF || echo "logging_collector = on" >> $POSTGRESQL_CONF

# Update pg_hba.conf to allow connections
if ! grep -q "host    all             all" $POSTGRESQL_PG_HBA; then
    echo "host    all             all             0.0.0.0/0               md5" >> $POSTGRESQL_PG_HBA
fi

# Update systemd service to use new data directory
echo "Updating PostgreSQL systemd service..."
SYSTEMD_OVERRIDE="/etc/systemd/system/postgresql.service.d/override.conf"
mkdir -p /etc/systemd/system/postgresql.service.d
cat > $SYSTEMD_OVERRIDE <<EOF
[Service]
Environment=PGDATA=$POSTGRESQL_DATA_DIR
ExecStart=
ExecStart=/usr/lib/postgresql/$POSTGRESQL_VERSION/bin/postgres -D $POSTGRESQL_DATA_DIR -c config_file=$POSTGRESQL_CONF
EOF

systemctl daemon-reload

# Set PostgreSQL admin password
echo "Setting PostgreSQL admin password..."
sudo -u postgres psql -c "ALTER USER postgres PASSWORD '$POSTGRESQL_ADMIN_PASSWORD';" || true

# Start PostgreSQL
echo "Starting PostgreSQL service..."
systemctl start postgresql
systemctl enable postgresql

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
sleep 5
RETRIES=30
count=0
while [ $count -lt $RETRIES ]; do
    if sudo -u postgres psql -c "SELECT 1;" > /dev/null 2>&1; then
        echo "PostgreSQL is ready"
        break
    fi
    
    count=$((count+1))
    echo "Waiting for PostgreSQL... Attempt $count of $RETRIES"
    sleep 5
done

if [ $count -eq $RETRIES ]; then
    echo "ERROR: PostgreSQL did not start properly"
    exit 1
fi

# Create database
echo "Creating database: $DATABASE_NAME"
sudo -u postgres psql -c "CREATE DATABASE $DATABASE_NAME;" || echo "Database may already exist"

# Create database user
echo "Creating database user: $DATABASE_USER"
sudo -u postgres psql -c "CREATE USER $DATABASE_USER WITH PASSWORD '$DATABASE_PASSWORD';" || echo "User may already exist"

# Grant privileges
echo "Granting privileges..."
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DATABASE_NAME TO $DATABASE_USER;"
sudo -u postgres psql -d $DATABASE_NAME -c "GRANT ALL ON SCHEMA public TO $DATABASE_USER;"

# Create a test table
echo "Creating test table..."
sudo -u postgres psql -d $DATABASE_NAME -c "CREATE TABLE IF NOT EXISTS test_table (id SERIAL PRIMARY KEY, message TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);" || true

echo "PostgreSQL setup completed successfully at $(date)"
echo "PostgreSQL data directory: $POSTGRESQL_DATA_DIR"
echo "Database: $DATABASE_NAME"
echo "User: $DATABASE_USER"
echo "Port: $POSTGRESQL_PORT"

