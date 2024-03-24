// THIS FILE IS NOT USED, JUST KEPT HERE FOR REFERENCE AS POSSIBLE FUTURE STUFF

bring "@cdktf/provider-aws" as aws;
bring "cdktf" as cdktf;
bring cloud;

let bucketName = "factorio-server-data";
let bucket = new cloud.Bucket();
let bucketRaw: aws.s3Bucket.S3Bucket = unsafeCast(new cloud.Bucket());
let files = ["config/server-adminlist.json", "config/server-settings.json", "mods/mod-list.json"];
let copyConfig = MutJson {};
for f in files {
  let bucketKey = "factorio/${f}";
  bucket.addFile(bucketKey, "./{f}");
  copyConfig.set(bucketKey, {
    owner: "factorio",
    group: "factorio",
    mode: "0664",
    source: {
      S3: {
        BucketName: bucketRaw.bucket,
        Key: bucketKey
      }
    }
  });
}

let containerDefinition = Json {
  "name": "config-sidecar",
  "essential": true,
  "image": "public.ecr.aws/compose-x/ecs-files-composer:latest",
  "mountPoints": [
    {
      "sourceVolume": "factorio",
      "readOnly": false,
      "containerPath": "/factorio"
    }
  ],
  environment: [
    {
      "name": "AWS_DEFAULT_REGION",
      "value": "us-east-2"
    },
    {
      "name": "ECS_CONFIG_CONTENT",
      "value": cdktf.Fn.jsonencode(copyConfig)
    }
  ]
};
