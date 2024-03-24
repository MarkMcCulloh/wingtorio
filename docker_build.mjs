#!/usr/bin/env bun
import { $ } from "bun";

// ensure the secrets are set
if (!process.env.FACTORIO_USERNAME) {
  throw "FACTORIO_USERNAME is not set";
}

if (!process.env.FACTORIO_TOKEN) {
  throw "FACTORIO_TOKEN is not set";
}

// check that docker is installed
const existingArgs = process.argv.slice(2);
if (existingArgs.length === 0) {
  throw "No arguments provided";
}

await $`docker buildx build --secret id=username,env=FACTORIO_USERNAME --secret id=token,env=FACTORIO_TOKEN ${existingArgs}`