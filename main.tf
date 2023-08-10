resource "aws_vpc" "myvpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "PROD_vpc"
  }

}

resource "aws_subnet" "public_subnet_01" {
  vpc_id                  = aws_vpc.myvpc.id
  cidr_block              = var.cidr_block01
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "PROD_subnet01"
  }
}

resource "aws_subnet" "public_subnet_02" {
  vpc_id                  = aws_vpc.myvpc.id
  cidr_block              = var.cidr_block02
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = true
  tags = {
    Name = "PROD_subnet02"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.myvpc.id
  tags = {
    Name = "PROD_gateway"
  }
}

resource "aws_route_table" "RT" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "rta1" {
  subnet_id      = aws_subnet.public_subnet_01.id
  route_table_id = aws_route_table.RT.id
}

resource "aws_route_table_association" "rta2" {
  subnet_id      = aws_subnet.public_subnet_02.id
  route_table_id = aws_route_table.RT.id
}

resource "aws_security_group" "Web-sg" {
  name   = "PROD_Web-sg"
  vpc_id = aws_vpc.myvpc.id

  dynamic "ingress" {
    for_each = [
      {
        description = "http from VPC"
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
      },
      {
        description = "SSH"
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
      },
    ]

    content {
      description = ingress.value["description"]
      from_port   = ingress.value["from_port"]
      to_port     = ingress.value["to_port"]
      protocol    = ingress.value["protocol"]
      cidr_blocks = ingress.value["cidr_blocks"]
    }
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "PROD_Web-sg"
  }
}


resource "aws_s3_bucket" "example" {
  bucket = "seeniya-tf-test-bucket"
}

resource "aws_s3_bucket_public_access_block" "public_access_block" {
  bucket = aws_s3_bucket.example.id
  block_public_acls   = true
  block_public_policy = true
  ignore_public_acls  = true
  restrict_public_buckets = true
}

# Create a bucket policy to allow access from the EC2 instance
resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.example.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = ["s3:GetObject"],
        Effect = "Allow",
        Resource = "${aws_s3_bucket.example.arn}/*",
        Principal = {
          Service = "ec2.amazonaws.com",
          AWS     = aws_iam_role.ec2_role.arn
        }
      }
    ]
  })
}
resource "aws_iam_instance_profile" "exampleprofile" {
  name = "my-iam-instance-profile"
  role = aws_iam_role.ec2_role.name
}

# Create an IAM role for EC2 instance
resource "aws_iam_role" "ec2_role" {
  name = "instance_roleabc"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach AmazonS3ReadOnlyAccess policy to the IAM role
resource "aws_iam_policy_attachment" "ec2_role_attachment" {
  name       = "ec2-s3-policy-attachment"
  roles      = [aws_iam_role.ec2_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}


resource "aws_instance" "webserver1" {
  ami                    = "ami-0430580de6244e02e"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnet_01.id
  vpc_security_group_ids = [aws_security_group.Web-sg.id]
  key_name      = "seeniya-aws-key-2023"
  user_data              = base64encode(file("userdata.sh"))
  tags = {
    Name = "PROD_server_01" # Assign the desired name to the "Name" tag
  }

}

resource "aws_instance" "webserver2" {
  ami                    = "ami-0430580de6244e02e"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnet_02.id
  vpc_security_group_ids = [aws_security_group.Web-sg.id]
  key_name      = "seeniya-aws-key-2023"
  iam_instance_profile = aws_iam_instance_profile.exampleprofile.name
  user_data              = base64encode(file("userdata1.sh"))
  tags = {
    Name = "PROD_server_02" # Assign the desired name to the "Name" tag
  }
}

resource "aws_instance" "webserver3" {
  ami                    = "ami-0430580de6244e02e"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnet_02.id
  vpc_security_group_ids = [aws_security_group.Web-sg.id]
  key_name      = "seeniya-aws-key-2023"
  user_data              = base64encode(file("userdata2.sh"))
  tags = {
    Name = "PROD_server_03" # Assign the desired name to the "Name" tag
  }
}

# Create a VPC endpoint for S3
resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id       = aws_vpc.myvpc.id
  service_name = "com.amazonaws.us-east-2.s3"  # Replace with your desired region
  route_table_ids         = [aws_route_table.RT.id]
}

# Update the route table to route S3 traffic through the VPC endpoint
resource "aws_route" "s3_route" {
  route_table_id         = aws_route_table.RT.id
  destination_cidr_block = "0.0.0.0/0"  # This routes all traffic to the endpoint
  gateway_id                = aws_internet_gateway.gw.id

 # vpc_endpoint_id = aws_vpc_endpoint.s3_endpoint.id
}

# Associate the subnet with the updated route table
resource "aws_route_table_association" "s3_association" {
  subnet_id      = aws_subnet.public_subnet_01.id
  route_table_id = aws_route_table.RT.id
}

resource "aws_lb" "myalb" {
  name               = "myalb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.Web-sg.id]
  subnets            = [aws_subnet.public_subnet_01.id, aws_subnet.public_subnet_02.id]
  tags = {
    Name        = "PROD_LoadBalancer"
    Environment = "production"
  }
}

resource "aws_lb_target_group" "tg" {
  name     = "myTG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.myvpc.id
  health_check {
    path = "/"
    port = "traffic-port"
  }
}

resource "aws_lb_target_group_attachment" "attach1" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.webserver1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "attach2" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.webserver2.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "attach3" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.webserver3.id
  port             = 80
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.myalb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}
output "loadbalancerdns" {
  value = aws_lb.myalb.dns_name
}