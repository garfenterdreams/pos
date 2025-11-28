#!/bin/bash
# Garfenter Cloud - OpenSourcePOS Docker Entrypoint
# Auto-initializes database and sets up test users

set -e

# Wait for MySQL to be ready
wait_for_mysql() {
    echo "Waiting for MySQL to be ready..."
    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if php -r "
            \$host = getenv('DB_HOST') ?: 'localhost';
            \$user = getenv('DB_USER') ?: 'admin';
            \$pass = getenv('DB_PASS') ?: 'pointofsale';
            \$db = getenv('DB_NAME') ?: 'ospos';
            try {
                \$pdo = new PDO(\"mysql:host=\$host;dbname=\$db\", \$user, \$pass);
                exit(0);
            } catch (Exception \$e) {
                exit(1);
            }
        " 2>/dev/null; then
            echo "MySQL is ready!"
            return 0
        fi

        attempt=$((attempt + 1))
        echo "Attempt $attempt/$max_attempts - MySQL not ready yet..."
        sleep 2
    done

    echo "Warning: MySQL may not be fully ready, continuing anyway..."
    return 0
}

# Initialize database if tables don't exist
init_database() {
    echo "Checking if database needs initialization..."

    local host="${DB_HOST:-localhost}"
    local user="${DB_USER:-admin}"
    local pass="${DB_PASS:-pointofsale}"
    local db="${DB_NAME:-ospos}"

    # Check if ospos_app_config table exists
    if ! php -r "
        \$host = '$host';
        \$user = '$user';
        \$pass = '$pass';
        \$db = '$db';
        try {
            \$pdo = new PDO(\"mysql:host=\$host;dbname=\$db\", \$user, \$pass);
            \$result = \$pdo->query(\"SHOW TABLES LIKE 'ospos_app_config'\");
            exit(\$result->rowCount() > 0 ? 0 : 1);
        } catch (Exception \$e) {
            exit(1);
        }
    " 2>/dev/null; then
        echo "Initializing database with tables.sql..."
        mysql -h "$host" -u "$user" -p"$pass" "$db" < /app/app/Database/tables.sql 2>/dev/null || true

        echo "Applying database constraints..."
        mysql -h "$host" -u "$user" -p"$pass" "$db" < /app/app/Database/constraints.sql 2>/dev/null || true

        echo "Database initialized successfully!"
    else
        echo "Database already initialized, skipping..."
    fi
}

# Update admin password to Garfenter standard
update_admin_password() {
    echo "Updating admin password to Garfenter standard..."

    local host="${DB_HOST:-localhost}"
    local user="${DB_USER:-admin}"
    local pass="${DB_PASS:-pointofsale}"
    local db="${DB_NAME:-ospos}"

    # Generate bcrypt hash for GarfenterAdmin2024
    local new_password_hash=$(php -r "echo password_hash('GarfenterAdmin2024', PASSWORD_DEFAULT);")

    php -r "
        \$host = '$host';
        \$user = '$user';
        \$pass = '$pass';
        \$db = '$db';
        try {
            \$pdo = new PDO(\"mysql:host=\$host;dbname=\$db\", \$user, \$pass);
            \$stmt = \$pdo->prepare(\"UPDATE ospos_employees SET password = ? WHERE username = 'admin'\");
            \$stmt->execute(['$new_password_hash']);
            echo \"Admin password updated successfully!\n\";
        } catch (Exception \$e) {
            echo \"Warning: Could not update admin password: \" . \$e->getMessage() . \"\n\";
        }
    " 2>/dev/null || true
}

# Main entrypoint
main() {
    echo "=== Garfenter Cloud - OpenSourcePOS Startup ==="

    # Wait for MySQL
    wait_for_mysql

    # Initialize database if needed
    init_database

    # Update admin password
    update_admin_password

    echo "=== Starting Apache ==="

    # Start Apache in foreground
    exec apache2-foreground "$@"
}

main "$@"
