provider "aws" {
  region = "eu-west-1"
}

##############################################################
# Data sources to get VPC, subnets and security group details
##############################################################
data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "all" {
  vpc_id = "${data.aws_vpc.default.id}"
}

data "aws_security_group" "default" {
  vpc_id = "${data.aws_vpc.default.id}"
  name   = "default"
}

data "aws_ami" "amazon_linux" {
  most_recent = true

  filter {
    name = "name"

    values = [
      "amzn-ami-hvm-*-x86_64-gp2",
    ]
  }

  filter {
    name = "owner-alias"

    values = [
      "amazon",
    ]
  }
}

######
# Launch configuration and autoscaling group
######
module "example_asg" {
  source = "../../"

  name = "example-with-elb"

  # Launch configuration
  #
  # launch_configuration = "my-existing-launch-configuration" # Use the existing launch configuration
  # create_lc = false # disables creation of launch configuration
  lc_name = "example-lc"

  image_id        = "${data.aws_ami.amazon_linux.id}"
  instance_type   = "t2.micro"
  security_groups = ["${data.aws_security_group.default.id}"]
  load_balancers  = ["${module.elb.this_elb_id}"]

  ebs_block_device = [
    {
      device_name           = "/dev/xvdz"
      volume_type           = "gp2"
      volume_size           = "10"
      delete_on_termination = true
    },
  ]

  root_block_device = [
    {
      volume_size = "50"
      volume_type = "gp2"
    },
  ]

  # Auto scaling group
  asg_name                  = "example-asg"
  vpc_zone_identifier       = ["${data.aws_subnet_ids.all.ids}"]
  health_check_type         = "EC2"
  min_size                  = 0
  max_size                  = 1
  desired_capacity          = 0
  wait_for_capacity_timeout = 0

  tags = [
    {
      key                 = "Environment"
      value               = "dev"
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "megasecret"
      propagate_at_launch = true
    },
  ]

  # Without passing an additional variable - You will have to use -target for this
  # scaling_notifications = [
  # {
  # topic_arn = "${module.sns_topic.this_sns_topic_arn}"
  # },
  # {
  # topic_arn = "${module.notify_slack.this_slack_topic_arn}"
  #
  # notifications = "${join(",", list(
  # "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
  # "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  # ))}"
  # },
  # ]

  # Require additional variable
  computed_scaling_notifications = [
    {
      topic_arn = "${module.sns_topic.this_sns_topic_arn}"
    },
    {
      topic_arn = "${module.notify_slack.this_slack_topic_arn}"

      notifications = "${join(",", list(
        "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
        "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
      ))}"
    },
  ]
  number_of_computed_scaling_notifications = 2
}

######
# ELB
######
module "elb" {
  source = "terraform-aws-modules/elb/aws"

  name = "elb-example"

  subnets         = ["${data.aws_subnet_ids.all.ids}"]
  security_groups = ["${data.aws_security_group.default.id}"]
  internal        = false

  listener = [
    {
      instance_port     = "80"
      instance_protocol = "HTTP"
      lb_port           = "80"
      lb_protocol       = "HTTP"
    },
  ]

  health_check = [
    {
      target              = "HTTP:80/"
      interval            = 30
      healthy_threshold   = 2
      unhealthy_threshold = 2
      timeout             = 5
    },
  ]

  tags = {
    Owner       = "user"
    Environment = "dev"
  }
}

######
# SNS
######
module "sns_topic" {
  source = "terraform-aws-modules/sns/aws"

  sns_topic_name = "scaling-events"
}

module "notify_slack" {
  source = "terraform-aws-modules/notify-slack/aws"

  sns_topic_name = "scaling-errors"

  slack_webhook_url = "https://hooks.slack.com/services/AAA/BBB/CCC"
  slack_channel     = "aws-notification"
  slack_username    = "reporter"
}
