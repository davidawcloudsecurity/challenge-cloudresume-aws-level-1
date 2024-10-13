variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "ami" {
  description = "Amazon Linux 2 AMI ID"
  default     = "ami-02c21308fed24a8ab" # Amazon Linux 2 AMI (HVM) - Kernel 5.10, SSD Volume Type in us-east-1
}

provider "aws" {
  region = var.region
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "main-vpc"
  }
}

# Subnets
resource "aws_subnet" "public_facing" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet"
  }
}

resource "aws_subnet" "private_app" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true # temp for ssm

  tags = {
    Name = "private-app-subnet"
  }
}

resource "aws_subnet" "private_db" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true # temp for ssm

  tags = {
    Name = "private-db-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}


# NAT Gateway
resource "aws_eip" "nat_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_facing.id

  tags = {
    Name = "main-nat"
  }
}

# Route Tables
resource "aws_route_table" "public_facing" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-facing-route-table"
  }
}

resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private-app-route-table"
  }
}

resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private-db-route-table"
  }
}

resource "aws_route_table_association" "public_facing" {
  subnet_id      = aws_subnet.public_facing.id
  route_table_id = aws_route_table.public_facing.id
}

resource "aws_route_table_association" "private_app" {
  subnet_id      = aws_subnet.private_app.id
  route_table_id = aws_route_table.private_app.id
}

resource "aws_route_table_association" "private_db" {
  subnet_id      = aws_subnet.private_db.id
  route_table_id = aws_route_table.private_db.id
}

# Security Groups
resource "aws_security_group" "public_facing" {
  name        = "allow_http_ssh"
  description = "Allow HTTP and SSH inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_http_ssh"
  }
}

resource "aws_security_group" "private_app" {
  name        = "allow_nginx"
  description = "Allow HTTP inbound traffic within VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from public subnet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    #    cidr_blocks = [aws_security_group.public_facing.id]
    security_groups = [aws_security_group.public_facing.id]
  }

  ingress {
    description = "Setup to allow SSM"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  /* remove as it is on private_db
  ingress {
    description = "MYSQL/Aurora from private subnet"
    from_port   = 3306
    to_port     = 3306
    protocol    = "TCP"
    self        = true
  }
*/
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_nginx"
  }
}

resource "aws_security_group" "private_db" {
  name        = "allow_wordpress"
  description = "Allow HTTP inbound traffic within VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from private subnet app tier"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    #    cidr_blocks = [aws_security_group.public.id]
    security_groups = [aws_security_group.private_app.id]
  }
  /* Remove to test
  ingress {
    description = "Setup to allow SSM"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]    
#    cidr_blocks = [aws_security_group.public.id]
#    security_groups = [aws_security_group.private_app.id]
  }  
*/
  ingress {
    description = "MYSQL/Aurora from private subnet app tier"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "SSM from AWS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_wordpress"
  }
}

# IAM Role for EC2 Instances
resource "aws_iam_role" "ec2_ssm_role" {
  name = "ec2_ssm_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.ec2_ssm_role.name
}

resource "aws_iam_instance_profile" "ec2_ssm_profile" {
  name = "ec2_ssm_profile"
  role = aws_iam_role.ec2_ssm_role.name
}

# EC2 Instances
resource "aws_instance" "nginx" {
  ami                    = var.ami
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_facing.id
  vpc_security_group_ids = [aws_security_group.public_facing.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm_profile.name

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install docker -y
              service docker start
              usermod -a -G docker ec2-user
              docker pull nginx
              
              # Create a custom NGINX configuration to point to the WordPress instance
              cat << EOF1 > /home/ec2-user/default.conf
              server {
                  listen 80;
                  server_name localhost;
              
                  location / {
                      proxy_pass http://${aws_instance.wordpress.private_ip};
                      proxy_set_header Host \$host;
                      proxy_set_header X-Real-IP \$remote_addr;
                      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
                      proxy_set_header X-Forwarded-Proto \$scheme;
                  }
              }
              EOF1

              docker run -d -p 80:80 --name nginx-demo nginx;
              # Wait until the nginx-demo container is running
              while [ "$(docker inspect -f '{{.State.Running}}' nginx-demo)" != "true" ]; do
                  echo "Waiting for nginx-demo to start..."
                  sleep 1
              done
              docker cp /home/ec2-user/default.conf nginx-demo:/etc/nginx/conf.d;
              docker exec nginx-demo nginx -s reload;
              EOF

  tags = {
    Name = "nginx-instance"
  }
}

resource "aws_instance" "wordpress" {
  ami                    = var.ami
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_app.id
  vpc_security_group_ids = [aws_security_group.private_app.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm_profile.name

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install docker -y
              service docker start
              usermod -a -G docker ec2-user
              docker run -d -e WORDPRESS_DB_HOST=${aws_instance.mysql.private_ip}:3306 \
                         -e WORDPRESS_DB_USER=wordpress \
                         -e WORDPRESS_DB_PASSWORD=wordpress \
                         -e WORDPRESS_DB_NAME=wordpress \
                         -p 80:80 wordpress
              EOF

  tags = {
    Name = "wordpress-instance"
  }
}

resource "aws_instance" "mysql" {
  ami                    = var.ami
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_db.id
  vpc_security_group_ids = [aws_security_group.private_db.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm_profile.name

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install docker -y
              service docker start
              usermod -a -G docker ec2-user
              docker run -d -e MYSQL_ROOT_PASSWORD=rootpassword \
                         -e MYSQL_DATABASE=wordpress \
                         -e MYSQL_USER=wordpress \
                         -e MYSQL_PASSWORD=wordpress \
                         -p 3306:3306 mysql:5.7
              EOF

  tags = {
    Name = "mysql-instance"
  }
}

output "seeds" {
  value = [aws_instance.nginx.private_ip, aws_instance.wordpress.private_ip, aws_instance.mysql.private_ip]
}
