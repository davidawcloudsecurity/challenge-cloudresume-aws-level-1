# challenge-cloudresume-aws-level-1
How To Setup A 3 Tier Web Architecture With NGINX, Wordpress and MSSQL Using EC2 Instance
```bash
tail -v /var/log/cloud-init-output.log
```
## Setup aliases for shortcuts
```ruby
alias tf="terraform"; alias tfa="terraform apply --auto-approve"; alias tfd="terraform destroy --auto-approve"; alias tfm="terraform init; terraform fmt; terraform validate; terraform plan"
```
## Run this if running at cloudshell
How to install terraform - https://developer.hashicorp.com/terraform/install
```ruby
sudo yum install -y yum-utils shadow-utils; sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo; sudo yum -y install terraform; terraform init
```
## How to install Wordpress, nginx, and mariadb in AWS Linux2
```bash
sudo amazon-linux-extras install php7.4
sudo yum install -y mariadb-server
```
mariadb
```bash
#!/bin/bash

# Variables
db_name="wp_$(date +%s)"
db_user=$db_name
db_password=$(date | md5sum | cut -c 1-12)
mysql_root_password=$(date | md5sum | cut -c 1-12)

# Save credentials to a file
cat > /tmp/db_credentials <<EOF
db_name=${db_name}
db_user=${db_user}
db_password=${db_password}
mysql_root_password=${mysql_root_password}
EOF
chmod 600 /tmp/db_credentials

# Update and install necessary packages
apt update -y
apt upgrade -y

# Install MariaDB
apt install -y mariadb-server mariadb-client
systemctl enable mariadb
systemctl start mariadb

# Secure MariaDB installation
mysql_secure_installation <<EOF

n
y
y
y
y
EOF

# Set up MySQL root password and create WordPress database and user
mysql -u root <<MYSQL_SCRIPT
ALTER USER 'root'@'localhost' IDENTIFIED BY '${mysql_root_password}';
CREATE DATABASE ${db_name};
CREATE USER '${db_user}'@'localhost' IDENTIFIED BY '${db_password}';
GRANT ALL PRIVILEGES ON ${db_name}.* TO '${db_user}'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# Check if database and user were created successfully
if mysql -u root -p${mysql_root_password} -e "USE ${db_name}"; then
    echo "Database '${db_name}' created successfully."
else
    echo "Database creation failed."
    exit 1
fi

# Store MySQL root password in ~/.my.cnf for easier access
cat > ~/.my.cnf <<EOF
[client]
user=root
password=${mysql_root_password}
EOF
chmod 600 ~/.my.cnf

# Final checks
if systemctl status mariadb | grep "active (running)" && mysql -u root -p${mysql_root_password} -e "USE ${db_name}"; then
    # Print out installation details only if everything is successful
    echo "Database setup complete!"
    echo "Database Name: ${db_name}"
    echo "Database User: ${db_user}"
    echo "Database Password: ${db_password}"
    echo "MySQL root password: ${mysql_root_password}"
else
    echo "Database setup failed. Please check the logs for more information."
    exit 1
fi
```
Wordpress. Just remember to change db_name, db_user, db_password and mysql_root_password if you are using the cred from above
```bash
#!/bin/bash

# Variables
install_dir="/var/www/html/wordpress"
db_name="wp_$(date +%s)"
db_user=$db_name
db_password=$(date | md5sum | cut -c 1-12)
mysql_root_password=$(date | md5sum | cut -c 1-12)
db_host="192.168.0.203"

# Update and install necessary packages
apt update -y
apt upgrade -y

# Install Apache
apt install -y apache2
systemctl enable apache2
systemctl start apache2

# Change Apache to run on port 3000
sed -i 's/80/3000/g' /etc/apache2/ports.conf
sed -i 's/:80/:3000/g' /etc/apache2/sites-available/000-default.conf

# Restart Apache to apply port change
systemctl restart apache2

# Check if Apache is running
if systemctl status apache2 | grep "active (running)"; then
    echo "Apache is running on port 3000."
else
    echo "Apache failed to start."
    exit 1
fi

# Install PHP and required modules
apt install -y php libapache2-mod-php php-mysql php-cli php-curl php-xml php-mbstring php-gd

# Download and extract WordPress
mkdir -p ${install_dir}
cd /tmp
wget -q https://wordpress.org/latest.tar.gz
if [[ $? -ne 0 ]]; then
    echo "Failed to download WordPress."
    exit 1
fi

tar -xzf latest.tar.gz
mv wordpress/* ${install_dir}

# Check if WordPress files are in place
if [ -d "${install_dir}" ]; then
    echo "WordPress files extracted successfully."
else
    echo "WordPress extraction failed."
    exit 1
fi

# Set permissions
chown -R www-data:www-data ${install_dir}
chmod -R 755 ${install_dir}

# Configure WordPress wp-config.php
cp ${install_dir}/wp-config-sample.php ${install_dir}/wp-config.php

# Update wp-config.php with DB details
sed -i "s/database_name_here/${db_name}/" ${install_dir}/wp-config.php
sed -i "s/username_here/${db_user}/" ${install_dir}/wp-config.php
sed -i "s/password_here/${db_password}/" ${install_dir}/wp-config.php
sed -i "s/localhost/${db_host}/" ${install_dir}/wp-config.php

# Add security keys (salts) to wp-config.php
curl -s https://api.wordpress.org/secret-key/1.1/salt/ >> ${install_dir}/wp-config.php

# Enable Apache mods for WordPress (rewrite for pretty permalinks)
a2enmod rewrite
sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf

# Restart Apache to apply changes
systemctl restart apache2

# Ensure port 3000 is open in firewall (if ufw is used)
ufw allow 3000/tcp

# Final installation checks
if systemctl status apache2 | grep "active (running)" && mysql -h ${db_host} -u root -p${mysql_root_password} -e "USE ${db_name}"; then
    # Print out installation details only if everything is successful
    echo "Installation complete!"
    echo "WordPress has been installed in ${install_dir}"
    echo "Database Host: ${db_host}"
    echo "Database Name: ${db_name}"
    echo "Database User: ${db_user}"
    echo "Database Password: ${db_password}"
    echo "MySQL root password: ${mysql_root_password}"
    echo "Apache is running on port 3000"
else
    echo "Installation failed. Please check the logs for more information."
    exit 1
fi
```
