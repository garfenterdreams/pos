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
                \$pdo = new PDO(\"mysql:host=\$host;dbname=\$db\", \$user, \$pass, [
                    PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT => false
                ]);
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

    # Check if ospos_app_config table exists using PHP
    local tables_exist=$(php -r "
        \$host = '$host';
        \$user = '$user';
        \$pass = '$pass';
        \$db = '$db';
        try {
            \$pdo = new PDO(\"mysql:host=\$host;dbname=\$db\", \$user, \$pass, [
                PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT => false
            ]);
            \$result = \$pdo->query(\"SHOW TABLES LIKE 'ospos_app_config'\");
            echo \$result->rowCount() > 0 ? 'yes' : 'no';
        } catch (Exception \$e) {
            echo 'no';
        }
    " 2>/dev/null)

    if [ "$tables_exist" = "no" ]; then
        echo "Initializing database with tables.sql..."

        # Execute tables.sql using PHP/PDO
        php -r "
            \$host = '$host';
            \$user = '$user';
            \$pass = '$pass';
            \$db = '$db';
            try {
                \$pdo = new PDO(\"mysql:host=\$host;dbname=\$db\", \$user, \$pass, [
                    PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT => false
                ]);
                \$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

                // Read and execute tables.sql
                \$sql = file_get_contents('/app/app/Database/tables.sql');
                // Split by semicolons but handle multi-line INSERT statements
                \$statements = preg_split('/;[\r\n]+/', \$sql);
                foreach (\$statements as \$stmt) {
                    \$stmt = trim(\$stmt);
                    if (!empty(\$stmt) && \$stmt !== '--') {
                        try {
                            \$pdo->exec(\$stmt);
                        } catch (Exception \$e) {
                            // Ignore duplicate key errors for INSERT statements
                            if (strpos(\$e->getMessage(), 'Duplicate') === false) {
                                echo 'Warning: ' . \$e->getMessage() . \"\\n\";
                            }
                        }
                    }
                }
                echo \"Tables created successfully!\\n\";

                // Read and execute constraints.sql
                \$sql = file_get_contents('/app/app/Database/constraints.sql');
                \$statements = preg_split('/;[\r\n]+/', \$sql);
                foreach (\$statements as \$stmt) {
                    \$stmt = trim(\$stmt);
                    if (!empty(\$stmt) && \$stmt !== '--') {
                        try {
                            \$pdo->exec(\$stmt);
                        } catch (Exception \$e) {
                            // Ignore constraint errors (may already exist)
                            if (strpos(\$e->getMessage(), 'Duplicate') === false &&
                                strpos(\$e->getMessage(), 'already exists') === false) {
                                echo 'Warning: ' . \$e->getMessage() . \"\\n\";
                            }
                        }
                    }
                }
                echo \"Constraints applied successfully!\\n\";
            } catch (Exception \$e) {
                echo 'Error initializing database: ' . \$e->getMessage() . \"\\n\";
                exit(1);
            }
        " 2>&1

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

    php -r "
        \$host = '$host';
        \$user = '$user';
        \$pass = '$pass';
        \$db = '$db';
        try {
            \$pdo = new PDO(\"mysql:host=\$host;dbname=\$db\", \$user, \$pass, [
                PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT => false
            ]);
            \$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

            // Generate bcrypt hash for GarfenterAdmin2024
            \$newPasswordHash = password_hash('GarfenterAdmin2024', PASSWORD_DEFAULT);

            \$stmt = \$pdo->prepare(\"UPDATE ospos_employees SET password = ? WHERE username = 'admin'\");
            \$stmt->execute([\$newPasswordHash]);

            if (\$stmt->rowCount() > 0) {
                echo \"Admin password updated to GarfenterAdmin2024\\n\";
            } else {
                echo \"Admin user not found or password already set\\n\";
            }
        } catch (Exception \$e) {
            echo 'Warning: Could not update admin password: ' . \$e->getMessage() . \"\\n\";
        }
    " 2>&1
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
