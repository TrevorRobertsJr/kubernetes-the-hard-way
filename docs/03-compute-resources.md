# Provisioning Compute Resources

Kubernetes requires a set of machines to host the Kubernetes control plane and the worker nodes where containers are ultimately run. In this lab you will provision the compute resources required for running a secure and highly available Kubernetes cluster across a single [availability zone](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html).

> Ensure a default compute zone and region have been set as described in the [Prerequisites](01-prerequisites.md#configure-credentials-and-the-aws-region) lab.

## Networking

The Kubernetes [networking model](https://kubernetes.io/docs/concepts/cluster-administration/networking/#kubernetes-model) assumes a flat network in which containers and nodes can communicate with each other. In cases where this is not desired [network policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) can limit how groups of containers are allowed to communicate with each other and external network endpoints.

> Setting up network policies is out of scope for this tutorial.

### Virtual Private Cloud Network

In this section a dedicated [Virtual Private Cloud](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-getting-started.html) (VPC) network will be setup to host the Kubernetes cluster.

Create the `kubernetes-the-hard-way` custom VPC network:


```
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.240.0.0/16 | \
  jq -r '.Vpc.VpcId')
```

```
aws ec2 create-tags \
  --resources ${VPC_ID} \
  --tags Key=Name,Value=kubernetes
```

```
aws ec2 modify-vpc-attribute \
  --vpc-id ${VPC_ID} \
  --enable-dns-support '{"Value": true}'
```

```
aws ec2 modify-vpc-attribute \
  --vpc-id ${VPC_ID} \
  --enable-dns-hostnames '{"Value": true}'
```

### DHCP Option Sets

```
DHCP_OPTION_SET_ID=$(aws ec2 create-dhcp-options \
  --dhcp-configuration "Key=domain-name,Values=$AWS_REGION.compute.internal" \
    "Key=domain-name-servers,Values=AmazonProvidedDNS" | \
  jq -r '.DhcpOptions.DhcpOptionsId')
```

```
aws ec2 create-tags \
  --resources ${DHCP_OPTION_SET_ID} \
  --tags Key=Name,Value=kubernetes
```

```
aws ec2 associate-dhcp-options \
  --dhcp-options-id ${DHCP_OPTION_SET_ID} \
  --vpc-id ${VPC_ID}
```

### Internet Gateways

```
INTERNET_GATEWAY_ID=$(aws ec2 create-internet-gateway | \
  jq -r '.InternetGateway.InternetGatewayId')
```

```
aws ec2 create-tags \
  --resources ${INTERNET_GATEWAY_ID} \
  --tags Key=Name,Value=kubernetes
```

```
aws ec2 attach-internet-gateway \
  --internet-gateway-id ${INTERNET_GATEWAY_ID} \
  --vpc-id ${VPC_ID}


A [subnet](https://cloud.google.com/compute/docs/vpc/#vpc_networks_and_subnets) must be provisioned with an IP address range large enough to assign a private IP address to each node in the Kubernetes cluster.

Create the `kubernetes` subnet in the `kubernetes-the-hard-way` VPC network:

```
SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id ${VPC_ID} \
  --cidr-block 10.240.0.0/24 | \
  jq -r '.Subnet.SubnetId')
```

```
aws ec2 create-tags \
  --resources ${SUBNET_ID} \
  --tags Key=Name,Value=kubernetes
```

> The `10.240.0.0/24` IP address range can host up to 254 compute instances.

### Route Tables

```
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
  --vpc-id ${VPC_ID} | \
  jq -r '.RouteTable.RouteTableId')
```

```
aws ec2 create-tags \
  --resources ${ROUTE_TABLE_ID} \
  --tags Key=Name,Value=kubernetes
```

```
aws ec2 associate-route-table \
  --route-table-id ${ROUTE_TABLE_ID} \
  --subnet-id ${SUBNET_ID}
```

```
aws ec2 create-route \
  --route-table-id ${ROUTE_TABLE_ID} \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id ${INTERNET_GATEWAY_ID}
```

### Firewall Rules

Create a firewall rule that allows internal communication across all protocols:

```
gcloud compute firewall-rules create kubernetes-the-hard-way-allow-internal \
  --allow tcp,udp,icmp \
  --network kubernetes-the-hard-way \
  --source-ranges 10.240.0.0/24,10.200.0.0/16
```

Create a firewall rule that allows external SSH, ICMP, and HTTPS:

```
gcloud compute firewall-rules create kubernetes-the-hard-way-allow-external \
  --allow tcp:22,tcp:6443,icmp \
  --network kubernetes-the-hard-way \
  --source-ranges 0.0.0.0/0
```

> An [external load balancer](https://cloud.google.com/compute/docs/load-balancing/network/) will be used to expose the Kubernetes API Servers to remote clients.


```
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
  --group-name kubernetes \
  --description "Kubernetes security group" \
  --vpc-id ${VPC_ID} | \
  jq -r '.GroupId')
```

```
aws ec2 create-tags \
  --resources ${SECURITY_GROUP_ID} \
  --tags Key=Name,Value=kubernetes
```

```
aws ec2 authorize-security-group-ingress \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol all
```

```
aws ec2 authorize-security-group-ingress \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol all \
  --port 0-65535 \
  --cidr 10.240.0.0/16
```

```
aws ec2 authorize-security-group-ingress \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0
```

```
aws ec2 authorize-security-group-ingress \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol tcp \
  --port 6443 \
  --cidr 0.0.0.0/0
```

```
aws ec2 authorize-security-group-ingress \
  --group-id ${SECURITY_GROUP_ID} \
  --protocol all \
  --source-group ${SECURITY_GROUP_ID}
```


### Kubernetes Public IP Address

An ELB will be used to load balance traffic across the Kubernetes control plane.

```
aws elb create-load-balancer \
  --load-balancer-name kubernetes \
  --listeners "Protocol=TCP,LoadBalancerPort=6443,InstanceProtocol=TCP,InstancePort=6443" \
  --subnets ${SUBNET_ID} \
  --security-groups ${SECURITY_GROUP_ID}
```

## Compute Instances

All the VMs in this lab will be provisioned using Ubuntu 16.04 mainly because it runs a newish Linux Kernel that has good support for Docker.

All virtual machines in this section will be created with the `--no-source-dest-check` flag to enable traffic between foreign subnets to flow. The will enable Pods to communicate with nodes and other Pods via the Kubernetes service IP.

### Create Instance IAM Policies

```
cat > kubernetes-iam-role.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {"Effect": "Allow", "Principal": { "Service": "ec2.amazonaws.com"}, "Action": "sts:AssumeRole"}
  ]
}
EOF
```

```
aws iam create-role \
  --role-name kubernetes \
  --assume-role-policy-document file://kubernetes-iam-role.json
```

```
cat > kubernetes-iam-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {"Effect": "Allow", "Action": ["ec2:*"], "Resource": ["*"]},
    {"Effect": "Allow", "Action": ["elasticloadbalancing:*"], "Resource": ["*"]},
    {"Effect": "Allow", "Action": ["route53:*"], "Resource": ["*"]},
    {"Effect": "Allow", "Action": ["ecr:*"], "Resource": "*"}
  ]
}
EOF
```

```
aws iam put-role-policy \
  --role-name kubernetes \
  --policy-name kubernetes \
  --policy-document file://kubernetes-iam-policy.json
```

```
aws iam create-instance-profile \
  --instance-profile-name kubernetes 
```

```
aws iam add-role-to-instance-profile \
  --instance-profile-name kubernetes \
  --role-name kubernetes
```

### Chosing an Image

Pick the latest Ubuntu Xenial server

```
IMAGE_ID=$(aws ec2 describe-images --owners 099720109477 \
  --region $AWS_REGION \
  --filters Name=root-device-type,Values=ebs Name=architecture,Values=x86_64 'Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*' \
  | jq -r '.Images|sort_by(.Name)[-1]|.ImageId')
```

### Generate A SSH Key Pair

```
aws ec2 create-key-pair --key-name kubernetes | \
  jq -r '.KeyMaterial' > ~/.ssh/kubernetes_the_hard_way
```

```
chmod 600 ~/.ssh/kubernetes_the_hard_way
```

```
ssh-add ~/.ssh/kubernetes_the_hard_way 
```

The compute instances in this lab will be provisioned using [Ubuntu Server](https://www.ubuntu.com/server) 18.04, which has good support for the [containerd container runtime](https://github.com/containerd/containerd). Each compute instance will be provisioned with a fixed private IP address to simplify the Kubernetes bootstrapping process.

### Kubernetes Controllers

Create three compute instances which will host the Kubernetes control plane:

```
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
```

```
aws ec2 modify-instance-attribute \
  --instance-id ${CONTROLLER_0_INSTANCE_ID} \
  --no-source-dest-check
```

```
aws ec2 create-tags \
  --resources ${CONTROLLER_0_INSTANCE_ID} \
  --tags Key=Name,Value=controller0
``` 

```
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
```

```
aws ec2 modify-instance-attribute \
  --instance-id ${CONTROLLER_1_INSTANCE_ID} \
  --no-source-dest-check
```

```
aws ec2 create-tags \
  --resources ${CONTROLLER_1_INSTANCE_ID} \
  --tags Key=Name,Value=controller1
``` 

```
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
```

```
aws ec2 modify-instance-attribute \
  --instance-id ${CONTROLLER_2_INSTANCE_ID} \
  --no-source-dest-check
```

```
aws ec2 create-tags \
  --resources ${CONTROLLER_2_INSTANCE_ID} \
  --tags Key=Name,Value=controller2
``` 

### Kubernetes Workers

Each worker instance requires a pod subnet allocation from the Kubernetes cluster CIDR range. The pod subnet allocation will be used to configure container networking in a later exercise. The `pod-cidr` instance metadata will be used to expose pod subnet allocations to compute instances at runtime.

> The Kubernetes cluster CIDR range is defined by the Controller Manager's `--cluster-cidr` flag. In this tutorial the cluster CIDR range will be set to `10.200.0.0/16`, which supports 254 subnets.

Create three compute instances which will host the Kubernetes worker nodes:

```
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
```

```
aws ec2 modify-instance-attribute \
  --instance-id ${WORKER_0_INSTANCE_ID} \
  --no-source-dest-check
```

```
aws ec2 create-tags \
  --resources ${WORKER_0_INSTANCE_ID} \
  --tags Key=Name,Value=worker0
```

```
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
```

```
aws ec2 modify-instance-attribute \
  --instance-id ${WORKER_1_INSTANCE_ID} \
  --no-source-dest-check
```

```
aws ec2 create-tags \
  --resources ${WORKER_1_INSTANCE_ID} \
  --tags Key=Name,Value=worker1
```

```
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
```

```
aws ec2 modify-instance-attribute \
  --instance-id ${WORKER_2_INSTANCE_ID} \
  --no-source-dest-check
```

```
aws ec2 create-tags \
  --resources ${WORKER_2_INSTANCE_ID} \
  --tags Key=Name,Value=worker2
```


## Verify

```
aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" "Name=vpc-id,Values=${VPC_ID}" | \
  jq -j '.Reservations[].Instances[] | .InstanceId, "  ", .Placement.AvailabilityZone, "  ", .PrivateIpAddress, "  ", .PublicIpAddress, "\n"'
```
```
i-ae714f73  us-west-2c  10.240.0.11  XX.XX.XX.XXX
i-f4714f29  us-west-2c  10.240.0.21  XX.XX.XXX.XXX
i-f6714f2b  us-west-2c  10.240.0.12  XX.XX.XX.XX
i-e26e503f  us-west-2c  10.240.0.22  XX.XX.XXX.XXX
i-e8714f35  us-west-2c  10.240.0.10  XX.XX.XXX.XXX
i-78704ea5  us-west-2c  10.240.0.20  XX.XX.XXX.XXX
```

## Configuring SSH Access

#### SSH Access

Once the virtual machines are created you'll be able to login into each machine using ssh like this:

```
WORKER_0_PUBLIC_IP_ADDRESS=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=worker0" | \
    jq -j '.Reservations[].Instances[].PublicIpAddress')
```

> The instance public IP address can also be obtained from the EC2 console. Each node will be tagged with a unique name.

```
ssh ubuntu@${WORKER_0_PUBLIC_IP_ADDRESS}
```


SSH will be used to configure the controller and worker instances. When connecting to compute instances for the first time SSH keys will be generated for you and stored in the project or instance metadata as describe in the [connecting to instances](https://cloud.google.com/compute/docs/instances/connecting-to-instance) documentation.

Test SSH access to the `controller-0` compute instances:

```
gcloud compute ssh controller-0
```

If this is your first time connecting to a compute instance SSH keys will be generated for you. Enter a passphrase at the prompt to continue:

```
WARNING: The public SSH key file for gcloud does not exist.
WARNING: The private SSH key file for gcloud does not exist.
WARNING: You do not have an SSH key for gcloud.
WARNING: SSH keygen will be executed to generate a key.
Generating public/private rsa key pair.
Enter passphrase (empty for no passphrase):
Enter same passphrase again:
```

At this point the generated SSH keys will be uploaded and stored in your project:

```
Your identification has been saved in /home/$USER/.ssh/google_compute_engine.
Your public key has been saved in /home/$USER/.ssh/google_compute_engine.pub.
The key fingerprint is:
SHA256:nz1i8jHmgQuGt+WscqP5SeIaSy5wyIJeL71MuV+QruE $USER@$HOSTNAME
The key's randomart image is:
+---[RSA 2048]----+
|                 |
|                 |
|                 |
|        .        |
|o.     oS        |
|=... .o .o o     |
|+.+ =+=.+.X o    |
|.+ ==O*B.B = .   |
| .+.=EB++ o      |
+----[SHA256]-----+
Updating project ssh metadata...-Updated [https://www.googleapis.com/compute/v1/projects/$PROJECT_ID].
Updating project ssh metadata...done.
Waiting for SSH key to propagate.
```

After the SSH keys have been updated you'll be logged into the `controller-0` instance:

```
Welcome to Ubuntu 18.04 LTS (GNU/Linux 4.15.0-1006-gcp x86_64)

...

Last login: Sun May 13 14:34:27 2018 from XX.XXX.XXX.XX
```

Type `exit` at the prompt to exit the `controller-0` compute instance:

```
$USER@controller-0:~$ exit
```
> output

```
logout
Connection to XX.XXX.XXX.XXX closed
```

Next: [Provisioning a CA and Generating TLS Certificates](04-certificate-authority.md)
