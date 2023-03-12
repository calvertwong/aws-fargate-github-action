# create virtual private cloud
# cidr_block is a range of IPv4 addresses for the VPC in the form of a Classless Inter-Domain Routing (CIDR) block
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "main-vpc"
  }
}

# create public subnet from the main_vpc ip pool
resource "aws_subnet" "public_subnet_west_2a" {
  vpc_id     = aws_vpc.main_vpc.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "public-subnet-west-2a"
  }
}

# create a second public subnet from the main_vpc ip pool
resource "aws_subnet" "public_subnet_west_2b" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-west-2d"

  tags = {
    Name = "public-subnet-west-2b"
  }
}

# create private subnet from the main_vpc ip pool
resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.3.0/24"
  map_public_ip_on_launch = false

  tags = {
    Name = "private-subnet"
  }
}

# create an internet gateway to allow subnet to access to the outside world
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "internet-gateway"
  }
}

resource "aws_route" "main_route_table" {
  route_table_id         = aws_vpc.main_vpc.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
}

resource "aws_security_group" "calvert-security-group" {
  name        = "calvert-security-group"
  description = "Cal Vert Security Group"
  vpc_id      = aws_vpc.main_vpc.id

  # Allow outbound internet access
  # from_port 0 and to_port 0 mean all ports
  # protocol -1 means any protocol
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "Outbound internet access"
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
  }

  tags = {
    "Name" = "calvert-security-group"
  }
}

resource "aws_ecr_repository" "dummy-node-ecr" {
  name = "dummy-node-ecr"
}

resource "aws_security_group" "alb_sg" {
  name_prefix = "alb-sg"
  vpc_id = aws_vpc.main_vpc.id

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

resource "aws_lb" "dummy_node_alb" {
  name               = "dummy-node-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [aws_security_group.alb_sg.id]
  subnets         = [aws_subnet.public_subnet_west_2a.id, aws_subnet.public_subnet_west_2b.id]

  tags = {
    Name = "dummy-node-alb"
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.dummy_node_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy = "ELBSecurityPolicy-2016-08"
  certificate_arn = "arn:aws:acm:us-west-2:267930273981:certificate/fcbc8f4f-03df-479e-84a8-825c63cdb5b7"
  
  default_action {
    target_group_arn = aws_lb_target_group.dummy_node_tg.arn
    type             = "forward"
  }
}

resource "aws_lb_target_group" "dummy_node_tg" {
  name_prefix = "prefix"
  port        = 3001
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main_vpc.id

  health_check {
    enabled  = true
    interval = 30
    path     = "/healthcheck"
    protocol = "HTTP"
    timeout  = 5
  }

  tags = {
    Name = "dummy-node-tg"
  }
}

resource "aws_ecs_cluster" "dummy_node_cluster" {
  name = "dummy-node-cluster"
}

resource "aws_ecs_task_definition" "dummy_node_task" {
  family = "dummy-node-task-family"
  container_definitions = jsonencode([
    {
      name  = "dummy-node-container"
      image = "nginx:latest"
      portMappings = [
        {
          containerPort = 3001
          hostPort      = 3001
        }
      ]
    }
  ])
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"

  cpu    = "256"
  memory = "512"
}

resource "aws_ecs_service" "dummy_node_service" {
  name            = "dummy-node-service"
  cluster         = aws_ecs_cluster.dummy_node_cluster.id
  task_definition = aws_ecs_task_definition.dummy_node_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    security_groups = [aws_security_group.alb_sg.id]
    subnets         = [aws_subnet.private_subnet.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.dummy_node_tg.arn
    container_name   = "dummy-node-lb-container"
    container_port   = 3001
  }

  depends_on = [
    aws_lb_listener.https,
  ]
}

