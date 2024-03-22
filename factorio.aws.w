bring "@cdktf/provider-aws" as aws;

pub class FactorioAws {
  new() {
    let baseCidrBlock = "10.0.1.0/24";

    let cluster = new aws.ecsCluster.EcsCluster(
      name: "factorio",
    );

    // add fargate capacity provider
    let capacityProvider = new aws.ecsClusterCapacityProviders.EcsClusterCapacityProviders(
      clusterName: cluster.name,
      capacityProviders: ["FARGATE"],
    );

    let containerConfig = Json [
      {
        "name": "factorio",
        "essential": true,
        "image": "factoriotools/factorio:stable",
        "portMappings": [
          {
            "containerPort": 34197,
            "hostPort": 34197,
            "protocol": "udp"
          },
          {
            "containerPort": 27015,
            "hostPort": 27015,
            "protocol": "tcp"
          }
        ],
        "logConfiguration": {
          "logDriver": "awslogs",
          "options": {
            "awslogs-group": "factorio",
            "awslogs-region": "us-east-2",
            "awslogs-stream-prefix": "factorio"
          }
        },
        "mountPoints": [
          {
            "sourceVolume": "factorio",
            "readOnly": false,
            "containerPath": "/factorio"
          }
        ],
      },
      {
        "name": "ubuntu",
        "essential": true,
        "image": "ubuntu",
        "command": ["sh", "-c", "wget https://filebin.net/fta6n5dcxduc1ybr/mods.tar.gz;tar -zxf mods.tar.gz -C /factorio/mods;"],
        "mountPoints": [
          {
            "sourceVolume": "factorio",
            "readOnly": false,
            "containerPath": "/factorio"
          }
        ],
      },
    ];

    new aws.cloudwatchLogGroup.CloudwatchLogGroup(name: "factorio");

    let executionRole = new aws.iamRole.IamRole(
      name: "factorio-execution-role",
      assumeRolePolicy: Json.stringify({
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Principal": {
              "Service": "ecs-tasks.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
          }
        ]
      })
    );

    let executionPolicy = new aws.iamPolicy.IamPolicy(
      name: "factorio-execution-policy",
      policy: Json.stringify({
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Action": [
              "logs:CreateLogStream",
              "logs:PutLogEvents",
              "logs:CreateLogGroup"
            ],
            "Resource": "*"
          }
        ]
      })
    );

    let executionRolePolicyAttachment = new aws.iamRolePolicyAttachment.IamRolePolicyAttachment(
      role: executionRole.name,
      policyArn: executionPolicy.arn
    );

    new aws.iamRolePolicyAttachment.IamRolePolicyAttachment(
      role: executionRole.name,
      policyArn: "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
    ) as "AmazonECSTaskExecutionRolePolicyAttachment";


    let vpc = new aws.vpc.Vpc(
      cidrBlock: baseCidrBlock,
      enableDnsSupport: true,
      enableDnsHostnames: true,
    );

    let publicSubnet = new aws.subnet.Subnet(
      vpcId: vpc.id,
      cidrBlock: baseCidrBlock,
      mapPublicIpOnLaunch: true,
    );

    let ig = new aws.internetGateway.InternetGateway(
      vpcId: vpc.id
    );

    let publicRouteTable = new aws.routeTable.RouteTable( 
      vpcId: vpc.id,
      route: [
        {
          // This will route all traffic to the internet gateway
          cidrBlock: "0.0.0.0/0",
          gatewayId: ig.id,
        },
      ],
    );

    new aws.routeTableAssociation.RouteTableAssociation(
      routeTableId: publicRouteTable.id,
      subnetId: publicSubnet.id,
    );

    let sg = new aws.securityGroup.SecurityGroup(
      vpcId: vpc.id,
      egress: [
        {
          fromPort: 0,
          toPort: 0,
          protocol: "-1",
          cidrBlocks: ["0.0.0.0/0"]
        },
      ],
      ingress: [
        {
          fromPort: 27015,
          toPort: 27015,
          protocol: "tcp",
          cidrBlocks: ["0.0.0.0/0"]
        },
        {
          fromPort: 34197,
          toPort: 34197,
          protocol: "udp",
          cidrBlocks: ["0.0.0.0/0"]
        },
        {
          fromPort: 2049,
          toPort: 2049,
          protocol: "tcp",
          cidrBlocks: ["0.0.0.0/0"]
        },
        {
          fromPort: 22,
          toPort: 22,
          protocol: "tcp",
          cidrBlocks: ["0.0.0.0/0"],
        }
      ]
    );

    // efs
    let efs = new aws.efsFileSystem.EfsFileSystem(
      lifecycle: {
        preventDestroy: true,
      }
    ) as "EFS2";

    let mountTarget = new aws.efsMountTarget.EfsMountTarget(
      fileSystemId: efs.id,
      subnetId: publicSubnet.id,
      securityGroups: [sg.id]
    );

    let taskRole = new aws.iamRole.IamRole(
      name: "factorio-task-role",
      assumeRolePolicy: Json.stringify({
        "Version": "2012-10-17",
        "Statement": [
          {
            "Effect": "Allow",
            "Principal": {
              "Service": "ecs-tasks.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
          },
        ]
      }),
      inlinePolicy: [{
        name: "mypolicy",
        policy: Json.stringify(
        {
          "Version": "2012-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Action": [
                "ssm:UpdateInstanceInformation",
                "ssmmessages:CreateControlChannel",
                "ssmmessages:CreateDataChannel",
                "ssmmessages:OpenControlChannel",
                "ssmmessages:OpenDataChannel"
              ],
              "Resource": "*"
            }
          ]
        })
      }]
    ) as "TaskRole";


    let taskDefinition = new aws.ecsTaskDefinition.EcsTaskDefinition(
      family: "factorio",
      containerDefinitions: Json.stringify(containerConfig),
      requiresCompatibilities: ["FARGATE"],
      networkMode: "awsvpc",
      cpu: "1024",
      memory: "2048",
      executionRoleArn: executionRole.arn,
      taskRoleArn: taskRole.arn,
      volume: [
        {
          name: "factorio",
          efsVolumeConfiguration: aws.ecsTaskDefinition.EcsTaskDefinitionVolumeEfsVolumeConfiguration {
            fileSystemId: efs.id,
          }
        }
      ]
    );

    let service = new aws.ecsService.EcsService(
      cluster: cluster.arn,
      taskDefinition: taskDefinition.arn,
      launchType: "FARGATE",
      desiredCount: 1,
      count: 1,
      name: "factorio",
      enableExecuteCommand: true,
      networkConfiguration: {
        assignPublicIp: true,
        subnets: [publicSubnet.id],
        securityGroups: [sg.id]
      },
    );
  }
}