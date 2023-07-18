# Create the VPC
resource "aws_vpc" "pine_vpc" {
  cidr_block = "10.10.0.0/16"
  tags = {
    Name = "pine-vpc"
    env  = "pinedev"
    team = "config mgt"
  }
}

# Create public subnets
resource "aws_subnet" "public_subnet_1a" {
  vpc_id            = aws_vpc.pine_vpc.id
  cidr_block        = "10.10.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "public_subnet_1b" {
  vpc_id            = aws_vpc.pine_vpc.id
  cidr_block        = "10.10.2.0/24"
  availability_zone = "us-east-1b"
}

# Create private subnets
resource "aws_subnet" "private_subnet_1a" {
  vpc_id            = aws_vpc.pine_vpc.id
  cidr_block        = "10.10.3.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "private_subnet_1b" {
  vpc_id            = aws_vpc.pine_vpc.id
  cidr_block        = "10.10.4.0/24"
  availability_zone = "us-east-1b"
}

# Create NAT gateways
resource "aws_eip" "eip_1a" {
  vpc = true
}

resource "aws_eip" "eip_1b" {
  vpc = true
}

resource "aws_nat_gateway" "nat_gateway_1a" {
  allocation_id = aws_eip.eip_1a.id
  subnet_id     = aws_subnet.public_subnet_1a.id
}

resource "aws_nat_gateway" "nat_gateway_1b" {
  allocation_id = aws_eip.eip_1b.id
  subnet_id     = aws_subnet.public_subnet_1b.id
}

# Create Internet Gateway
resource "aws_internet_gateway" "pine_internet_gateway" {
  vpc_id = aws_vpc.pine_vpc.id
}

# Attach Internet Gateway to VPC
resource "aws_vpc_attachment" "pine_vpc_attachment" {
  vpc_id             = aws_vpc.pine_vpc.id
  internet_gateway_id = aws_internet_gateway.pine_internet_gateway.id
}

# Create Key Pair
resource "aws_key_pair" "pine_keypair" {
  key_name   = "pine-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDBkMqxvqysv3i/LhYSYziIu6PKrZ35ocKm4m7ZrAq/DiVn3vUVBf9PK7j+TXj2bGssC8cLLy11nHRbJGTLmRWhlTrYSN5qI1ofj7z0TLoztlJ2mZxzgXscHjC5bnvVh4foeOkkLlzF1asXzyJ8nlueB8syiAWdzK79LlyfOrT+hfSP2A4ZXyPf4v2t8wO8YASwZx8pMnqAayfx0O7gOLG54hCnDvh2kw+0GZa2X0DcAeNGASd4yMuWz3mQ8CFbN6fXATqOKSvWSfziitFt3wLsbkbL2rvY/QxFiPV5NNCjMyqFQAg9kY0bex8xh/ZtyupHJQzVqWlv5stphrHCj0N5jMyV user@host"
}

output "private_key_pem" {
  value = aws_key_pair.pine_keypair.private_key_pem
}

# Create Bastion Host
resource "aws_instance" "bastion_host" {
  ami                    = "ami-xxxxxxxx"  # Replace with the actual AMI ID for the bastion host
  instance_type          = "t2.micro"
  key_name               = "pine-key"
  vpc_security_group_ids = [aws_security_group.sg_2.id]
  subnet_id              = aws_subnet.public_subnet_1a.id
}

# Provision Connection from Bastion Host to Private Server
resource "null_resource" "bastion_to_private" {
  depends_on = [aws_instance.bastion_host]

  connection {
    type        = "ssh"
    host        = aws_instance.bastion_host.public_ip
    user        = "ec2-user"
    private_key = aws_key_pair.pine_keypair.private_key_pem
    timeout     = "2m"
  }

  provisioner "remote-exec" {
    inline = [
      "scp -i ~/.ssh/pine-key.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ec2-user@<PRIVATE_SERVER_IP>:~/.ssh/id_rsa",
      "chmod 400 ~/.ssh/id_rsa"
    ]
  }
}


# Create security groups
resource "aws_security_group" "sg_1" {
  name        = "sg_1"
  description = "Security Group for All"
  vpc_id      = aws_vpc.pine_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
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
}

resource "aws_security_group" "sg_2" {
  name        = "sg_2"
  description = "Security Group for Bastion Host"
  vpc_id      = aws_vpc.pine_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["<YOUR_IP>/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "sg_3" {
  name        = "sg_3"
  description = "Security Group for App Server"
  vpc_id      = aws_vpc.pine_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.sg_1.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = [aws_security_group.sg_2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "sg_4" {
  name        = "sg_4"
  description = "Security Group for DataBase"
  vpc_id      = aws_vpc.pine_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_3.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
# Create EC2 instances
resource "aws_instance" "appserver_1a" {
  ami                    = "ami-xxxxxxxx" # Replace with the actual AMI ID for Amazon Linux 2
  instance_type          = "t2.micro"
  key_name               = "pine-key"
  vpc_security_group_ids = [aws_security_group.sg_3.id]
  subnet_id              = aws_subnet.private_subnet_1a.id
  user_data              = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd.x86_64
    systemctl start httpd.service
    systemctl enable httpd.service
    echo "Hello World from \$(hostname -f)" > /var/www/html/index.html
    EOF

  tags = {
    Name = "pine-vpc"
    env  = "pinedev"
    team = "config mgt"
  }
}

resource "aws_instance" "appserver_1b" {
  ami                    = "ami-xxxxxxxx" # Replace with the actual AMI ID for Amazon Linux 2
  instance_type          = "t2.micro"
  key_name               = "pine-key"
  vpc_security_group_ids = [aws_security_group.sg_3.id]
  subnet_id              = aws_subnet.private_subnet_1b.id
  user_data              = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd.x86_64
    systemctl start httpd.service
    systemctl enable httpd.service
    echo "Hello World from \$(hostname -f)" > /var/www/html/index.html
    EOF

 tags = {
    Name = "pine-vpc"
    env  = "pinedev"
    team = "config mgt"
  }
}

# Create EFS volume
resource "aws_efs_file_system" "pine_efs" {
  creation_token = "pine-efs"
}

resource "aws_efs_mount_target" "mount_target_1a" {
  file_system_id  = aws_efs_file_system.pine_efs.id
  subnet_id       = aws_subnet.private_subnet_1a.id
  security_groups = [aws_security_group.sg_3.id]
}

resource "aws_efs_mount_target" "mount_target_1b" {
  file_system_id  = aws_efs_file_system.pine_efs.id
  subnet_id       = aws_subnet.private_subnet_1b.id
  security_groups = [aws_security_group.sg_3.id]
}

# Create S3 bucket
resource "aws_s3_bucket" "pine_bucket" {
  bucket = "pine-bucket"
}

# Create RDS pineSQL database
resource "aws_db_instance" "pine_db_instance" {
  identifier         = "pine-db-instance"
  engine             = "pinesql"
  instance_class     = "db.t2.micro"
  allocated_storage  = 20
  storage_type       = "gp2"
  username           = "pineuser"
  password           = "pinedev12345"
  db_subnet_group_name = aws_db_subnet_group.pine_db_subnet_group.name
}

resource "aws_db_subnet_group" "pine_db_subnet_group" {
  name       = "pine-db-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_1a.id, aws_subnet.private_subnet_1b.id]
}

# Create Application Load Balancer
resource "aws_lb" "pine_load_balancer" {
  name               = "pine-load-balancer"
  load_balancer_type = "application"
  subnets            = [aws_subnet.public_subnet_1a.id, aws_subnet.public_subnet_1b.id]
}

# Create Target Group for Load Balancer
resource "aws_lb_target_group" "pine_target_group" {
  name        = "pine-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.pine_vpc.id
  target_type = "instance"
  targets     = [aws_instance.appserver_1a.id, aws_instance.appserver_1b.id]
}

# Create Listener for Load Balancer
resource "aws_lb_listener" "pine_listener" {
  load_balancer_arn = aws_lb.pine_load_balancer.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.pine_target_group.arn
  }
}

# Create Auto Scaling Group
resource "aws_autoscaling_group" "pine_autoscaling_group" {
  name                 = "pine-autoscaling-group"
  min_size             = 2
  max_size             = 10
  desired_capacity     = 2
  vpc_zone_identifier  = [aws_subnet.private_subnet_1a.id, aws_subnet.private_subnet_1b.id]
  target_group_arns    = [aws_lb_target_group.pine_target_group.arn]
  launch_template {
    id      = aws_launch_template.pine_launch_template.id
    version = "$Latest"
  }
}

resource "aws_launch_template" "pine_launch_template" {
  name      = "pine-launch-template"
  image_id  = "<AMI_ID>" // Replace with the actual AMI ID for pineappserver
  instance_type = "t2.micro"
  security_group_ids = [aws_security_group.sg_3.id]
  key_name = "pine-key"
}

# Create SNS Topic
resource "aws_sns_topic" "pine_topic" {
  name = "pine-auto-scaling"
}

# Create SNS Subscription
resource "aws_sns_topic_subscription" "pine_subscription" {
  topic_arn = aws_sns_topic.pine_topic.arn
  protocol  = "email"
  endpoint  = "<YOUR_EMAIL>"
}

# Configure Auto Scaling Notifications
resource "aws_autoscaling_notification" "pine_notification" {
  group_names     = [aws_autoscaling_group.pine_autoscaling_group.name]
  notifications   = ["autoscaling:EC2_INSTANCE_LAUNCH", "autoscaling:EC2_INSTANCE_TERMINATE"]
  topic_arn       = aws_sns_topic.pine_topic.arn
}
