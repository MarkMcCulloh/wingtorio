# Wingtorio

Factorio server hosted in AWS, from 0 to deployed in a few minutes!

## Prerequisites

- Factorio Account
- Bun (Package Manager and script runner)
- Node (Used internally for wing)

## Setup

Create a `.env` file in the root directory with the following content:

```env
FACTORIO_USERNAME=<factorio username>
FACTORIO_TOKEN=<factorio service token>
```

This information is used to install/update mods during the docker build process.

## Usage

To deploy:

```sh
bun up
```

*(Note: Initial docker build and push may take a while for the first deployment)*

To destroy:

```sh
bun down
```

## Major Resources Created

- VPC
  - 1 Public Subnet
  - Internet Gateway
  - Public EIP
- NLB
- EFS Storage
- ECR
- ECS Cluster (Fargate Capacity Only)

## Very Rough Cost Estimate

Non-listed resources are negligible (or whoops I forgot).

- ~$0.050/hr (ECS Fargate at 1 vCPU)
- ~$0.005/hr (Public EIP)
- ~$0.030/hr (NLB)

Total: ~$0.085/hr, ~$2/day
