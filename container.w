bring "@cdktf/provider-aws" as aws;
bring "cdktf" as cdktf;
bring "@cdktf/provider-null" as null_provider;
bring "./helper" as helper;

struct RepositoryProps {
  directory: str;
  name: str;
}

pub class Repository {
  pub image: str;
  pub deps: Array<cdktf.ITerraformDependable>;

  new(props: RepositoryProps) {
    let deps = MutArray<cdktf.ITerraformDependable>[];

    let count = 5;

    let r = new aws.ecrRepository.EcrRepository(
      name: props.name,
      forceDelete: true,
      imageTagMutability: "IMMUTABLE",
    );

    deps.push(r);
    
    new aws.ecrLifecyclePolicy.EcrLifecyclePolicy(
      repository: r.name,
      policy: Json.stringify({
        rules: [
	        {
	          rulePriority: 1,
	          description: "Keep only the last {count} untagged images.",
	          selection: {
	            tagStatus: "untagged",
	            countType: "imageCountMoreThan",
	            countNumber: count
	          },
	          action: {
	            type: "expire"
	          }
	        }
	      ]
      })
    );

    let tag = helper.dirHash(props.directory);

    let image = "{r.repositoryUrl}:{tag}";
    let repoHost = cdktf.Fn.element(cdktf.Fn.split("/", r.repositoryUrl), 0);
    let arch = "linux/amd64";

    // null provider singleton
    let root = nodeof(this).root;
    let nullProviderId = "NullProvider";
    if !root.node.tryFindChild(nullProviderId)? {
      new null_provider.provider.NullProvider() as nullProviderId in root;
    }

    let dockerBuildPath = helper.projectPath("docker_build.mjs");
    
    // TODO Use docker provider together with aws_ecr_authorization_token
    let publish = new null_provider.resource.Resource(
      dependsOn: [r],
      triggers: {
        tag: image,
      },
      provisioners: [
        {
          type: "local-exec",
          command: [
            "set -eou pipefail",
            "{dockerBuildPath} --platform {arch} -t {image} {props.directory}",
            "aws ecr get-login-password | docker login --username AWS --password-stdin {repoHost}",
            "docker push {image}",
          ].join("\n")
        }
      ],
    );

    deps.push(publish);

    this.image = image;
    this.deps = deps.copy();
  }
}