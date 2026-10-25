#!/bin/bash
yum update -y
yum install -y httpd php php-mysqli
systemctl start httpd
systemctl enable httpd
cd /var/www/html
cat << 'EOF' > index.php
<?php
$servername = "${db_endpoint}";
$username = "admin";
$password = "${db_password}";
$dbname = "webappdb";

$conn = new mysqli($servername, $username, $password, $dbname);

if ($conn->connect_error) {
    die("Database Connection Failed: " . $conn->connect_error);
}
echo "<h1>Database Connected Successfully!</h1>";
echo "<p>Served from App Server: " . gethostname() . "</p>";
?>
EOF