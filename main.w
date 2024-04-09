bring "@cdktf/provider-aws" as aws;
bring "./container.w" as container;
bring "cdktf" as cdktf;
bring "./helper" as helper;
bring cloud;

let TCP_PORT = 27015;
let UDP_PORT = 34197;

let ALL_IPS = "0.0.0.0/0";
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

let ig = new aws.internetGateway.InternetGateway(vpcId: vpc.id);

let eip = new aws.eip.Eip(
  domain: "vpc",
  dependsOn: [ig],
);
new cloud.Endpoint(eip.publicIp, label: "Server IP");

let publicRouteTable = new aws.routeTable.RouteTable( 
  vpcId: vpc.id,
  route: [
    {
      cidrBlock: ALL_IPS,
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
      cidrBlocks: [ALL_IPS]
    },
  ],
  ingress: [
    {
      fromPort: TCP_PORT,
      toPort: TCP_PORT,
      protocol: "tcp",
      cidrBlocks: [ALL_IPS]
    },
    {
      fromPort: UDP_PORT,
      toPort: UDP_PORT,
      protocol: "udp",
      cidrBlocks: [ALL_IPS]
    },
    // EFS
    // TODO This can be refined to the specific ECS service
    {
      fromPort: 2049,
      toPort: 2049,
      protocol: "tcp",
      cidrBlocks: [baseCidrBlock]
    },
    // Allow Nodes to pull images from ECR via VPC endpoints
    {
      fromPort: 443,
      toPort: 443,
      protocol: "tcp",
      cidrBlocks: [baseCidrBlock]
    },
  ]
);

// vpc endpoint for ECR dkr
let ecrDkrEndpoint = new aws.vpcEndpoint.VpcEndpoint(
  vpcId: vpc.id,
  serviceName: "com.amazonaws.us-east-2.ecr.dkr",
  vpcEndpointType: "Interface",
  privateDnsEnabled: true,
  securityGroupIds: [sg.id],
  subnetIds: [publicSubnet.id],
) as "ECRDkrEndpoint";
// vpc endpoint for ECR api
let ecrApiEndpoint = new aws.vpcEndpoint.VpcEndpoint(
  vpcId: vpc.id,
  serviceName: "com.amazonaws.us-east-2.ecr.api",
  vpcEndpointType: "Interface",
  privateDnsEnabled: true,
  securityGroupIds: [sg.id],
  subnetIds: [publicSubnet.id],
) as "ECRApiEndpoint";
// vpc endpoint for CloudWatch
let cloudWatchEndpoint = new aws.vpcEndpoint.VpcEndpoint(
  vpcId: vpc.id,
  serviceName: "com.amazonaws.us-east-2.logs",
  vpcEndpointType: "Interface",
  privateDnsEnabled: true,
  securityGroupIds: [sg.id],
  subnetIds: [publicSubnet.id],
) as "CloudWatchEndpoint";
// vpc endpoint for ECS agent
let ecsAgentEndpoint = new aws.vpcEndpoint.VpcEndpoint(
  vpcId: vpc.id,
  serviceName: "com.amazonaws.us-east-2.ecs-agent",
  vpcEndpointType: "Interface",
  privateDnsEnabled: true,
  securityGroupIds: [sg.id],
  subnetIds: [publicSubnet.id],
) as "ECSAgentEndpoint";
// vpc endpoint for ECS telemetry
let ecsTelemetryEndpoint = new aws.vpcEndpoint.VpcEndpoint(
  vpcId: vpc.id,
  serviceName: "com.amazonaws.us-east-2.ecs-telemetry",
  vpcEndpointType: "Interface",
  privateDnsEnabled: true,
  securityGroupIds: [sg.id],
  subnetIds: [publicSubnet.id],
) as "ECSTelemetryEndpoint";

// vpc endpoint for S3
let s3Endpoint = new aws.vpcEndpoint.VpcEndpoint(
  vpcId: vpc.id,
  serviceName: "com.amazonaws.us-east-2.s3",
  vpcEndpointType: "Gateway",
  routeTableIds: [publicRouteTable.id],
) as "S3Endpoint";

// vpc endpoint for EFS

let nlb = new aws.lb.Lb(
  loadBalancerType: "network",
  securityGroups: [sg.id],
  subnetMapping: {
    subnet_id: publicSubnet.id,
    allocation_id: eip.id,
  },
);
let tgHealthCheck = Json {
  port: "{TCP_PORT}",
  protocol: "TCP",
  healthyThreshold: 2,
  unhealthyThreshold: 2,
  timeout: 5,
  interval: 15,
};

let targetGroupTCP = new aws.lbTargetGroup.LbTargetGroup(
  port: TCP_PORT,
  protocol: "TCP",
  targetType: "ip",
  vpcId: vpc.id,
  deregistrationDelay: "0",
  healthCheck: tgHealthCheck,
) as "TGTCP";

let targetGroupUDP = new aws.lbTargetGroup.LbTargetGroup(
  port: UDP_PORT,
  protocol: "UDP",
  targetType: "ip",
  vpcId: vpc.id,
  deregistrationDelay: "0",
  healthCheck: tgHealthCheck,
) as "TGUDP";

let listenerTCP = new aws.lbListener.LbListener(
  loadBalancerArn: nlb.arn,
  port: TCP_PORT,
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
  port: UDP_PORT,
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
  lifecycle: {
    preventDestroy: true,
  }
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
        containerPort: UDP_PORT,
        hostPort: UDP_PORT,
        protocol: "udp"
      },
      {
        containerPort: TCP_PORT,
        hostPort: TCP_PORT,
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
  cpu: "2048",
  memory: "4096",
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
  },
  dependsOn: Array<cdktf.ITerraformDependable> [
    listenerTCP, 
    listenerUDP,
    s3Endpoint,
    ecrApiEndpoint,
    ecrDkrEndpoint,
    ecsAgentEndpoint,
    ecsTelemetryEndpoint,
    cloudWatchEndpoint,
  ],
  loadBalancer: [
    {
      targetGroupArn: targetGroupTCP.arn,
      containerName: "factorio",
      containerPort: TCP_PORT,
    },
    {
      targetGroupArn: targetGroupUDP.arn,
      containerName: "factorio",
      containerPort: UDP_PORT,
    },
  ],
);
