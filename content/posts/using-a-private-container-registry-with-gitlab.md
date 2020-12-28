---
author: "oofnik"
title: "using a private container registry with gitlab"
summary: |
  In the process of migrating our CI from self-hosted Jenkins to GitLab, I've encountered a couple of hurdles.
tags:
  - GCP
  - gitlab
date: 2019-10-04T08:24:57+00:00
draft: false
---

This one took me a while to figure out.

Originally I planned to move to a self-hosted installation on GKE, but abandoned that idea after a while due to maintenance overhead. I did learn a lot, though.

Next option: [Gitlab.com](https://gitlab.com). GitLab Cloud offers a whole lot of features for free, including 2000 build minutes, unlimited private repositories, unlimited number of collaborators, issue boards, ... yeah, I don't know why we didn't migrate earlier either. 

## Setting it up

Since we're already on GCP, I wanted to continue using our private container registry instead of using the GitLab registry (even though they offer 10GB for free...). The [docs](https://docs.gitlab.com/ee/ci/docker/using_docker_images.html#define-an-image-from-a-private-container-registry) do a decent job outlining the process of using your own private container registry, but there's one point that they fail to make which you just kind of have to figure out yourself. 

They provide three options to authenticate against a private registry: a) provide static credentials, b) use a credential store, or c) use a credential helper.

I started with the third option.

Following their AWS example, I created a CI/CD variable named `DOCKER_AUTH_CONFIG` with the following content, hoping for the best:

```json
{
  "credHelpers": {
    "gcr.io": "gcr"
  }
}
```

But no dice.

They mention this bit in the [docs](https://docs.gitlab.com/ee/ci/docker/using_docker_images.html#using-credential-helpers):

>Make sure `docker-credential-ecr-login` is available in GitLab Runner’s `$PATH`.

Uh, okay, well I'm using their shared runners, so I have no idea what's in their `$PATH`. But apparently, despite the fact that [they themselves](https://docs.gitlab.com/ee/user/gitlab_com/#shared-runners) host their runners on Google Cloud Platform, `docker-credential-gcr` isn't.

Next I tried setting static credentials.

I [generated a service account(https://cloud.google.com/iam/docs/creating-managing-service-accounts) for my GCP project with the Storage Admin role, and used the key to [log in](https://cloud.google.com/container-registry/docs/advanced-authentication) to Google Container Registry from my local machine. This generates a Docker authentication file in `~/.docker/config.json`, which the GitLab guide instructs you to copy as a variable in to your CI/CD configuration.

That didn't work, either.

Turns out, when you do

```sh
$ docker login -u _json_key --password-stdin gcr.io < key-file.json
```

The credentials file gets created with some extra stuff that needs to be removed manually.

### Before:

```json
{
	"auths": {
		"gcr.io": {
			"auth": "[actual base64-encoded JSON service account key]"
		},
		"https://asia.gcr.io": {
			"auth": "[secret]",
			"email": "not@val.id"
...
		"https://us.gcr.io": {
			"auth": "[secret]",
			"email": "not@val.id"
		}
	},
	"HttpHeaders": {
		"User-Agent": "Docker-Client/19.03.2 (linux)"
	}
}
```

Which results in the following error when running a build:

    ERROR: Preparation failed: Error response from daemon: unauthorized: You don't have the needed permissions to perform this operation, and you may have invalid credentials. To authenticate your request, follow the steps in: https://cloud.google.com/container-registry/docs/advanced-authentication (executor_docker.go:188:0s)

### After:

Removing the irrelevant sections from the credentials file, we are left with the following:

```json
{
  "auths": {
    "gcr.io": {
      "auth": "[actual base64-encoded JSON service account key]"
    }
  }
}
```

Result: 

    Authenticating with credentials from $DOCKER_AUTH_CONFIG
    Pulling docker image gcr.io/[GCP_PROJECT]/[MY_IMAGE]:[TAG] ...
    Using docker image sha256:8af18e4c85bcada4f1c029120138053ac75f1261ba884774add731012f5c65ba for gcr.io/[GCP_PROJECT]/[MY_IMAGE]:[TAG] ...

And we're good!

We can now run builds using images in our private registry without hard-coding credentials in our CI manifest.

Maybe I'll open a PR (ehm, MR in GitLab-ese) to update the docs?

Link to the (minimally redacted) `gitlab-ci.yml` I used for this project [here](https://gist.github.com/oofnikj/aff92570f6c1c2d6dae00d25c39014d2).
