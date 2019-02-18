# Set region
AWS_REGION=us-west-2

# Create VPC
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.240.0.0/16 | \
  jq -r '.Vpc.VpcId')

aws ec2 create-tags \
  --resources ${VPC_ID} \
  --tags Key=Name,Value=kubernetes

aws ec2 modify-vpc-attribute \
  --vpc-id ${VPC_ID} \
  --enable-dns-support '{"Value": true}'

aws ec2 modify-vpc-attribute \
  --vpc-id ${VPC_ID} \
  --enable-dns-hostnames '{"Value": true}'

# Configure DHCP Options
DHCP_OPTION_SET_ID=$(aws ec2 create-dhcp-options \
  --dhcp-configuration "Key=domain-name,Values=us-west-2.compute.internal" \
    "Key=domain-name-servers,Values=AmazonProvidedDNS" | \
  jq -r '.DhcpOptions.DhcpOptionsId')

aws ec2 create-tags \
  --resources ${DHCP_OPTION_SET_ID} \
  --tags Key=Name,Value=kubernetes

aws ec2 associate-dhcp-options \
  --dhcp-options-id ${DHCP_OPTION_SET_ID} \
  --vpc-id ${VPC_ID}

# Create Subnet
SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id ${VPC_ID} \
  --cidr-block 10.240.0.0/24 | \
  jq -r '.Subnet.SubnetId')

aws ec2 create-tags \
  --resources ${SUBNET_ID} \
  --tags Key=Name,Value=kubernetes

# Create Internet Gateway and attach to the VPC
INTERNET_GATEWAY_ID=$(aws ec2 create-internet-gateway | \
  jq -r '.InternetGateway.InternetGatewayId')
aws ec2 create-tags \
  --resources ${INTERNET_GATEWAY_ID} \
  --tags Key=Name,Value=kubernetes
aws ec2 attach-internet-gateway \
  --internet-gateway-id ${INTERNET_GATEWAY_ID} \
  --vpc-id ${VPC_ID}

# Create Route Table and associate with subnets
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
  --vpc-id ${VPC_ID} | \
  jq -r '.RouteTable.RouteTableId')
aws ec2 create-tags \
  --resources ${ROUTE_TABLE_ID} \
  --tags Key=Name,Value=kubernetes
aws ec2 associate-route-table \
  --route-table-id ${ROUTE_TABLE_ID} \
  --subnet-id ${SUBNET_ID}
aws ec2 create-route \
  --route-table-id ${ROUTE_TABLE_ID} \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id ${INTERNET_GATEWAY_ID}

# Create Security Groups
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
  --group-name kubernetes \
  --description "Kubernetes security group" \
  --vpc-id ${VPC_ID} | \
  jq -r '.GroupId')
aws ec2 create-tags \
  --resources ${SECURITY_GROUP_ID} \
  --tags Key=Name,Value=kubernetes

aws ec2 authorize-security-group-ingress \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol all
aws ec2 authorize-security-group-ingress \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol all \
  --port 0-65535 \
  --cidr 10.240.0.0/16
aws ec2 authorize-security-group-ingress \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol tcp \
  --port 6443 \
  --cidr 0.0.0.0/0

aws elb create-load-balancer \
  --load-balancer-name kubernetes \
  --listeners "Protocol=TCP,LoadBalancerPort=6443,InstanceProtocol=TCP,InstancePort=6443" \
  --subnets ${SUBNET_ID} \
  --security-groups ${SECURITY_GROUP_ID}

# Xenial Ubuntu
IMAGE_ID="ami-0ac019f4fcb7cb7e6"

aws ec2 create-key-pair --key-name kubernetes | \
  jq -r '.KeyMaterial' > ~/.ssh/kubernetes_the_hard_way
chmod 600 ~/.ssh/kubernetes_the_hard_way
ssh-add ~/.ssh/kubernetes_the_hard_way 


# scp -i ~/

# PUBLIC_IP_ADDRESS=$(aws ec2 describe-instances \
#     --filters "Name=tag:Name,Values=etcd2" | \
#     jq -r '.Reservations[].Instances[].PublicIpAddress') &&
#   ssh ubuntu@${PUBLIC_IP_ADDRESS}




#   aws ec2 describe-instances --filters "Name=tag:Name,Values=etcd0" | jq -r '.Reservations[].Instances[].PublicIpAddress'

# Create Instances

# Kubernetes Desktop

# DESKTOP_INSTANCE_ID=$(aws ec2 run-instances \
#   --associate-public-ip-address \
#   --iam-instance-profile 'Name=kubernetes' \
#   --image-id ${IMAGE_ID} \
#   --count 1 \
#   --key-name kubernetes \
#   --security-group-ids ${SECURITY_GROUP_ID} \
#   --instance-type t2.small \
#   --private-ip-address 10.240.0.9 \
#   --subnet-id ${SUBNET_ID} | \
#   jq -r '.Instances[].InstanceId')
  
# aws ec2 modify-instance-attribute \
#   --instance-id ${DESKTOP_INSTANCE_ID} \
#   --no-source-dest-check

# aws ec2 create-tags \
#   --resources ${DESKTOP_INSTANCE_ID} \
#   --tags Key=Name,Value=desktop

# Kubernetes Controllers
CONTROLLER_0_INSTANCE_ID=$(aws ec2 run-instances \
  --associate-public-ip-address \
  --iam-instance-profile 'Name=kubernetes' \
  --image-id ${IMAGE_ID} \
  --count 1 \
  --key-name kubernetes \
  --security-group-ids ${SECURITY_GROUP_ID} \
  --instance-type t2.small \
  --private-ip-address 10.240.0.10 \
  --subnet-id ${SUBNET_ID} | \
  jq -r '.Instances[].InstanceId')

aws ec2 modify-instance-attribute \
  --instance-id ${CONTROLLER_0_INSTANCE_ID} \
  --no-source-dest-check

aws ec2 create-tags \
  --resources ${CONTROLLER_0_INSTANCE_ID} \
  --tags Key=Name,Value=controller0

CONTROLLER_1_INSTANCE_ID=$(aws ec2 run-instances \
  --associate-public-ip-address \
  --iam-instance-profile 'Name=kubernetes' \
  --image-id ${IMAGE_ID} \
  --count 1 \
  --key-name kubernetes \
  --security-group-ids ${SECURITY_GROUP_ID} \
  --instance-type t2.small \
  --private-ip-address 10.240.0.11 \
  --subnet-id ${SUBNET_ID} | \
  jq -r '.Instances[].InstanceId')


aws ec2 modify-instance-attribute \
  --instance-id ${CONTROLLER_1_INSTANCE_ID} \
  --no-source-dest-check

aws ec2 create-tags \
  --resources ${CONTROLLER_1_INSTANCE_ID} \
  --tags Key=Name,Value=controller1

CONTROLLER_2_INSTANCE_ID=$(aws ec2 run-instances \
  --associate-public-ip-address \
  --iam-instance-profile 'Name=kubernetes' \
  --image-id ${IMAGE_ID} \
  --count 1 \
  --key-name kubernetes \
  --security-group-ids ${SECURITY_GROUP_ID} \
  --instance-type t2.small \
  --private-ip-address 10.240.0.12 \
  --subnet-id ${SUBNET_ID} | \
  jq -r '.Instances[].InstanceId')

aws ec2 modify-instance-attribute \
  --instance-id ${CONTROLLER_2_INSTANCE_ID} \
  --no-source-dest-check

aws ec2 create-tags \
  --resources ${CONTROLLER_2_INSTANCE_ID} \
  --tags Key=Name,Value=controller2


# Kubernetes Workers

WORKER_0_INSTANCE_ID=$(aws ec2 run-instances \
  --associate-public-ip-address \
  --iam-instance-profile 'Name=kubernetes' \
  --image-id ${IMAGE_ID} \
  --count 1 \
  --key-name kubernetes \
  --security-group-ids ${SECURITY_GROUP_ID} \
  --instance-type t2.small \
  --private-ip-address 10.240.0.20 \
  --subnet-id ${SUBNET_ID} | \
  jq -r '.Instances[].InstanceId')

aws ec2 modify-instance-attribute \
  --instance-id ${WORKER_0_INSTANCE_ID} \
  --no-source-dest-check

aws ec2 create-tags \
  --resources ${WORKER_0_INSTANCE_ID} \
  --tags Key=Name,Value=worker0

WORKER_1_INSTANCE_ID=$(aws ec2 run-instances \
  --associate-public-ip-address \
  --iam-instance-profile 'Name=kubernetes' \
  --image-id ${IMAGE_ID} \
  --count 1 \
  --key-name kubernetes \
  --security-group-ids ${SECURITY_GROUP_ID} \
  --instance-type t2.small \
  --private-ip-address 10.240.0.21 \
  --subnet-id ${SUBNET_ID} | \
  jq -r '.Instances[].InstanceId')

aws ec2 modify-instance-attribute \
  --instance-id ${WORKER_1_INSTANCE_ID} \
  --no-source-dest-check

aws ec2 create-tags \
  --resources ${WORKER_1_INSTANCE_ID} \
  --tags Key=Name,Value=worker1

WORKER_2_INSTANCE_ID=$(aws ec2 run-instances \
  --associate-public-ip-address \
  --iam-instance-profile 'Name=kubernetes' \
  --image-id ${IMAGE_ID} \
  --count 1 \
  --key-name kubernetes \
  --security-group-ids ${SECURITY_GROUP_ID} \
  --instance-type t2.small \
  --private-ip-address 10.240.0.22 \
  --subnet-id ${SUBNET_ID} | \
  jq -r '.Instances[].InstanceId')

aws ec2 modify-instance-attribute \
  --instance-id ${WORKER_2_INSTANCE_ID} \
  --no-source-dest-check

aws ec2 create-tags \
  --resources ${WORKER_2_INSTANCE_ID} \
  --tags Key=Name,Value=worker2
# NEW Clean-Up:
EIP=$(aws ec2 allocate-address --domain vpc |jq -r '.AllocationId')
NLB=$(aws elbv2 create-load-balancer --name my-load-balancer --type network --subnet-mappings SubnetId=${SUBNET_ID},AllocationId=${EIP})
aws ec2 create-tags \
  --resources ${NLB} \
  --tags Key=Name,Value=kubernetes-the-hard-way




    "AllocationId": "eipalloc-01a3b5e232fd22866",
    "PublicIpv4Pool": "amazon",
    "Domain": "vpc"
}
8c8590100a7f:crt trevorr$ aws ec2 allocate-address --domain vpc |jq -r '.AllocationId'
eipalloc-067c6886a4c36de88

#    aws ec2 describe-instances --filters "Name=tag:Name,Values=etcd0" | jq -r '.Reservations[].Instances[].PublicIpAddress'\
#
#  aws ec2 describe-images \
#    --filters \
#        Name=owner-id,Values=602401143452 \
#        Name=virtualization-type,Values=hvm \
#        Name=root-device-type,Values=ebs \
#        Name=is-public,Values=true \
#        Name=name,Values=*Xenial* \
#    --output text \
#    --query 'max_by(Images[], &CreationDate).ImageId'