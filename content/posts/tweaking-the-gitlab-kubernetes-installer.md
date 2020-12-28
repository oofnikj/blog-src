---
author: "oofnik"
title: "tweaking the gitlab kubernetes installer"
summary: |
  GitLab has a lovely feature that can bring up a Kubernetes cluster and install build runners on it with a single click. But you can't tweak it.
tags:
  - gitlab
  - helm
  - kubernetes
  - tiller
date: 2019-10-09T15:11:14+00:00
draft: false
---

GitLab has a lovely feature that can bring up a Kubernetes cluster and install build runners on it with a single click. But you can't tweak it.

---

While that's nice for those who just want to get builds running quickly on their own infrastructure, we were looking for something a little more customizable.

## Out of the box

Although GitLab Cloud can currently only provision a cluster on Google Kubernetes Engine, it can connect to and manage any existing Kubernetes cluster as long as it's reachable via the web (an on-prem GitLab deployment doesn't have this requirement, of course). Once it's authenticated, you can use the GitLab UI to install Helm, which is required for installing the rest of the available applications like Prometheus or GitLab Runner.

I followed the [GitLab docs](https://gitlab.com/help/user/project/clusters/index.md#add-existing-kubernetes-cluster) on how to add my cluster, and everything seemed to be on track.

The snazzy UI makes use of the [GitLab Runner Helm chart](https://gitlab.com/gitlab-org/charts/gitlab-runner/tree/master) to deploy build runners to your cluster. Although the chart itself offers a lot of customization,  tweaking the chart values isn't an option if you're deploying via the UI. 

## Schedule conflict

Our cluster is composed of several node pools of non-uniform size. Specifically, we were looking for a way to tell GitLab to run builds with a certain tag only on the beefier nodes in our cluster. 

Unfortunately, at the time of writing, there is no way to define resource requests at the job level. There's an [open issue](https://gitlab.com/gitlab-org/gitlab-runner/issues/2902) and even a [merge request](https://gitlab.com/gitlab-org/gitlab-runner/merge_requests/874) with some traction addressing this very feature, but no word from the maintainers. 

Since the runner chart [supports](https://gitlab.com/gitlab-org/charts/gitlab-runner/blob/master/values.yaml#L281) setting a `NodeSelector` for the runners, what we can do instead is use Kubernetes labels to schedule our runners on a subset of nodes with a particular label, and then specify a tag in our CI job so it only runs on runners with the tag associated with that label.

Our beefy nodes are assigned the label key-value pair `runner: large`. So we match this in the runner configuration by passing a parameter to Helm:

    --set runners.nodeSelector.runner="large"

We also want to make sure that we don't schedule more than one runner per node, so we set a CPU request that's too big for our small nodes (0.94 CPU allocatable), but still schedulable on our big nodes (3.92 CPU allocatable):

    --set runners.builds.cpuRequests="3"

Second, we need to assign a tag to our souped-up runners indicating their beefy spec to jobs. This tag, `runner-large`, will later be specified in our pipeline job:

    --set runners.tags='runner-large'

Now that we know exactly how we want to configure our runner chart, we have two options: a) deploy Helm, Tiller, and the runner chart on our own, or b) use the UI to deploy Tiller and GitLab Runner to our cluster, then tweak it.

There are already a ton of examples out there on how to deploy charts with Helm.

I'm going to take you down the back route where we tweak an existing GitLab runner setup provisioned with the UI, without having to re-deploy.


## Lockdown

If you installed Tiller via the GitLab UI, logging in to your cluster and doing a `helm ls` to see what's what like I did will quickly reveal that something is amiss:

    Error: could not find tiller

The first non-standard thing GitLab does when it installs Tiller in your cluster is deploying it to its own namespace -- `gitlab-managed-apps` -- instead of the default `kube-system`.

We can tell Helm where to find Tiller either with the command-line flag `--tiller-namespace` or by setting the environment variable `TILLER_NAMESPACE`:

```sh
$ export TILLER_NAMESPACE=gitlab-managed-apps
$ helm ls --tiller-connection-timeout 30
Error: context deadline exceeded
```

Since Helm's default timeout is an obnoxiously long 5 minutes, we shorten it to 30 seconds, only to find out that something is still preventing us from gaining access.

The second non-standard thing GitLab does is it [deploys Tiller with TLS enabled](https://github.com/helm/helm/blob/master/docs/tiller_ssl.md). This makes communication between the Helm client and Tiller secure. But now not only do we need to authenticate to our cluster, we need a _separate_ set of credentials to authenticate to Tiller. Whew.

Here's a little shell snippet that will pull the certs and keys out of the Tiller secret and set some environment variables so Helm can use them:

```sh
export HELM_HOME=${HELM_HOME:-$HOME/.helm}
export TILLER_NAMESPACE=gitlab-managed-apps
export HELM_TLS_ENABLE=true
kubectl config set-context --current --namespace gitlab-managed-apps
kubectl get secret tiller-secret -ojsonpath='{.data.ca\.crt}'  | base64 -d > ${HELM_HOME}/ca.pem
kubectl get secret tiller-secret -ojsonpath='{.data.tls\.crt}' | base64 -d > ${HELM_HOME}/cert.pem
kubectl get secret tiller-secret -ojsonpath='{.data.tls\.key}' | base64 -d > ${HELM_HOME}/key.pem
```

**Warning!** If you already have Helm TLS certificates in `~/.helm`, **they will be overwritten**. 
Take a look at [this post](https://medium.com/nuvo-group-tech/configure-helm-tls-communication-with-multiple-kubernetes-clusters-5e58674352e2) for a guide on juggling multiple Kubernetes clusters with different sets of credentials for Helm. 

If all goes smoothly, you should be able to see your runner deployment with `helm ls`.

## Tweak it

Now that we finally have access to GitLab's Tiller, we can follow the official GitLab [docs](https://docs.gitlab.com/runner/install/kubernetes.html#updating-gitlab-runner-using-the-helm-chart) on how to update a runner deployed with Helm, adding in our extra flags from above:

```sh
// add GitLab Helm chart repo to our local Helm config
$ helm repo add gitlab https://charts.gitlab.io && helm repo update
// save current runner chart values
$ helm get values runner > values.yaml 
// merge in our updated configuration
$ helm upgrade --namespace gitlab-managed-apps \
    -f values.yaml \
    --set runners.nodeSelector.runner="large" \
    --set runners.builds.cpuRequests="3" \
    --set runners.tags="runner-large" \
    runner gitlab/gitlab-runner
```

Finally, we can confirm that the changes took hold by waiting a moment for the pods to restart, then looking up the manager pod and printing out its config:

```sh
$ RUNNER_POD=$(kubectl get pods -l app=runner-gitlab-runner -ojsonpath='{.items[0].metadata.name}')
$ kubectl exec $RUNNER_POD cat /home/gitlab-runner/.gitlab-runner/config.toml
```

With any luck you should see your configuration updated to reflect the new values you passed to Helm when updating your deployment.

Now in your `.gitlab-ci.yml`, you can add 

```yaml
beefy job:
  tags:
    - runner-large
```

for a particular job, and your build will only run on nodes with the `runner: large` label.

---

The moral of this story: If you want custom runner configuration, use your own damn Tiller.
