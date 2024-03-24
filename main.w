bring "@cdktf/provider-aws" as aws;
bring "./container.w" as container;
bring "cdktf" as cdktf;
bring "./helper" as helper;
bring cloud;

let baseCidrBlock = "10.0.1.0/24";
let logs = new aws.cloudwatchLogGroup.CloudwatchLogGroup(name: "factorio");

// Networking
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

let eip = new aws.eip.Eip(
  domain: "vpc",
  dependsOn: [ig],
);
new cloud.Endpoint(eip.publicIp, label: "Server IP");

let publicRouteTable = new aws.routeTable.RouteTable( 
  vpcId: vpc.id,
  route: [
    {
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
    // EFS
    // TODO This can be refined to the specific ECS service
    {
      fromPort: 2049,
      toPort: 2049,
      protocol: "tcp",
      cidrBlocks: ["10.0.1.0/24"]
    },
  ]
);

let nlb = new aws.lb.Lb(
  loadBalancerType: "network",
  subnetMapping: {
    subnet_id: publicSubnet.id,
    allocation_id: eip.id,
  },
);
let targetGroupTCP = new aws.lbTargetGroup.LbTargetGroup(
  port: 27015,
  protocol: "TCP",
  targetType: "ip",
  vpcId: vpc.id,
  deregistrationDelay: "0",
  healthCheck: {
    healthyThreshold: 2,
    unhealthyThreshold: 2,
    timeout: 5,
    interval: 15,
  },
) as "TargetGroupTCP";
let targetGroupUDP = new aws.lbTargetGroup.LbTargetGroup(
  port: 34197,
  protocol: "UDP",
  targetType: "ip",
  vpcId: vpc.id,
  deregistrationDelay: "0",
  healthCheck: {
    // Use TCP health check for UDP
    port: "27015",
    protocol: "TCP",
    healthyThreshold: 2,
    unhealthyThreshold: 2,
    timeout: 5,
    interval: 15,
  },
) as "TargetGroupUDP";

let listenerTCP = new aws.lbListener.LbListener(
  loadBalancerArn: nlb.arn,
  port: 27015,
  protocol: "TCP",
  defaultAction: [
    {
      type: "forward",
      targetGroupArn: targetGroupTCP.arn,
    },
  ],
) as "ListenerTCP";
let listenerUDP = new aws.lbListener.LbListener(
  loadBalancerArn: nlb.arn,
  port: 34197,
  protocol: "UDP",
  defaultAction: [
    {
      type: "forward",
      targetGroupArn: targetGroupUDP.arn,
    },
  ],
) as "ListenerUDP";

//

// Storage
let efs = new aws.efsFileSystem.EfsFileSystem(
  // lifecycle: {
  //   preventDestroy: true,
  // }
);
let mountTarget = new aws.efsMountTarget.EfsMountTarget(
  fileSystemId: efs.id,
  subnetId: publicSubnet.id,
  securityGroups: [sg.id]
);

//

// Cluster
let cluster = new aws.ecsCluster.EcsCluster(
  name: "factorio",
);
new aws.ecsClusterCapacityProviders.EcsClusterCapacityProviders(
  clusterName: cluster.name,
  capacityProviders: ["FARGATE"],
);

//
let ecr = new container.Repository(
  directory: helper.projectPath("docker"),
  name: "factorio",
);

let containerConfig = Json [
  {
    name: "factorio",
    essential: true,
    image: ecr.image,
    portMappings: [
      {
        containerPort: 34197,
        hostPort: 34197,
        protocol: "udp"
      },
      {
        containerPort: 27015,
        hostPort: 27015,
        protocol: "tcp"
      }
    ],
    logConfiguration: {
      logDriver: "awslogs",
      options: {
        "awslogs-group": logs.name,
        "awslogs-region": "us-east-2",
        "awslogs-stream-prefix": "factorio"
      }
    },
    mountPoints: [
      {
        sourceVolume: "factorio",
        readOnly: false,
        containerPath: "/factorio"
      }
    ],
  }
];

let executionRole = new aws.iamRole.IamRole(
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
  }),
  inlinePolicy: {
    name: "task-execution-policy",
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
        },
        {
          "Effect": "Allow",
          "Action": [
            "ecr:BatchGetImage",
            "ecr:GetDownloadUrlForLayer",
            "ecr:GetAuthorizationToken"
          ],
          "Resource": "*"
        }
      ]
    })
  }
) as "ExecutionRole";

let taskRole = new aws.iamRole.IamRole(
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
  })
) as "TaskRole";


let taskDefinition = new aws.ecsTaskDefinition.EcsTaskDefinition(
  family: "factorio",
  containerDefinitions: cdktf.Fn.jsonencode(containerConfig),
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
  ],
  dependsOn: ecr.deps,
);

let service = new aws.ecsService.EcsService(
  cluster: cluster.arn,
  taskDefinition: taskDefinition.arn,
  launchType: "FARGATE",
  desiredCount: 1,
  count: 1,
  name: "factorio",
  enableExecuteCommand: true,
  waitForSteadyState: true,
  forceNewDeployment: true,
  triggers: {
    // redeploy service every time
    redeployment: cdktf.Token.asString(cdktf.Fn.plantimestamp()),
  },
  deploymentMaximumPercent: 100,
  deploymentMinimumHealthyPercent: 0,
  networkConfiguration: {
    subnets: [publicSubnet.id],
    securityGroups: [sg.id],
    // TODO Use a VPC endpoint to access ECR then remove this
    assignPublicIp: true,
  },
  loadBalancer: [
    {
      targetGroupArn: targetGroupTCP.arn,
      containerName: "factorio",
      containerPort: 27015,
    },
    {
      targetGroupArn: targetGroupUDP.arn,
      containerName: "factorio",
      containerPort: 34197,
    },
  ],
);