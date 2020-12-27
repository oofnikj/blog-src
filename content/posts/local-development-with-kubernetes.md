---
author: "oofnik"
title: "local development with kubernetes"
summary: |
  I wrote this howto for work while learning Kubernetes, mostly for myself, but also for other devs to jump in and learn without racking up cloud costs.
tags:
  - helm
  - k3s
  - kubernetes
date: 2019-09-28T16:31:55+00:00
draft: false
---

With the knowledge that there are 234924385734 other similar blog posts out there, I'm sharing my take on getting started with Kubernetes.

**July 2020**: This post has been updated with instructions for the latest version of `k3s` at the time of writing (1.18.4), Ubuntu 18.04, and Helm 3.
A lot has changed in a year!

---

## Introduction

Kubernetes is a standard with more than one implementation. Each distribution caters to a different set of requirements and considerations. Much like the diversity of available Linux distributions, some Kubernetes distributions aim to be completely packed with all current and historical features and add-ons, while some aim to be as lightweight and portable as possible. This guide will focus on installing a distribution on the lighter end of the spectrum for the purposes of local testing and development, [k3s](https://k3s.io/) by Rancher Labs.

## Installation

`k3s` claims to be runnable on any Linux (amd64, armv7, arm64). For this guide we're running Ubuntu 18.04 LTS.

Install it with

{{< highlight sh >}}
$ curl -sfL https://get.k3s.io | sh -
{{< /highlight >}}

#### Disclaimer:

Piping a shell script straight from the internet is living on the edge. But you're probably following this in a throwaway VM anyway, right? Right? I mean, who goes running random commands they find on internet blogs on their local computers?

Anyway. The installation script will download the `k3s` binary to `/usr/local/bin` by default and add a `systemd` service definition to run the agent in server mode, listening on `https://localhost:6443`. It will start a local cluster of 1 node and write a Kubernetes config file to `/etc/rancher/k3s/k3s.yaml`.

### Client configuration

By default, `k3s` creates the config file with `0600` permissions (only root can read or write to it) because it contains authentication information for controlling your Kubernetes “cluster”.

In order to interact with our cluster as a non-root user, copy this config to your local user directory where your `kubectl` client expects it to be.

**NOTE:** If you've already got some cluster credentials stored in the default location, they will be overwritten by the following command!

{{< highlight sh >}}
$ mkdir -p ~/.kube
$ sudo k3s kubectl config view --raw > ~/.kube/config
{{< /highlight >}}

If you want to preserve your existing Kubernetes cluster authentication credentials, `kubectl` can merge two YAML configs together -- but be warned, it's a bit kludgy. 

First, copy the `k3s` credentials to a temporary file using the `kubectl` command that comes built-in to `k3s`:

{{< highlight sh >}}
$ sudo k3s kubectl config view --raw > ~/.kube/config-k3s
{{< /highlight >}}

Set the `KUBECONFIG` environment variable in your shell to point to the `k3s` configuration _in addition_ to your original config using the same syntax you'd use for appending multiple paths to a `PATH` variable:

{{< highlight sh >}}
$ export KUBECONFIG=~/.kube/config-k3s:~/.kube/config
{{< /highlight >}}

Now we merge the configurations together, replace the original, and clean up:

{{< highlight sh >}}
$ kubectl config view --raw > ~/.kube/config-merged
$ mv ~/.kube/config-merged ~/.kube/config
$ rm ~/.kube/config-k3s
$ unset KUBECONFIG
{{< /highlight >}}

You can now check to make sure both your original clusters and your new local `k3s` cluster are present:

{{< highlight sh >}}
$ kubectl config get-contexts
CURRENT   NAME        CLUSTER     AUTHINFO   NAMESPACE
*         cluster-1   cluster-1   default    
          default     default     default    
{{< /highlight >}}

Now let's set our `k3s` cluster (named `default` by default) as the current context:

{{< highlight sh >}}
$ kubectl config use-context default
{{< /highlight >}}

You might want to rename the nondescript `default` with a more descriptive name:

{{< highlight sh >}}
$ kubectl config rename-context default k3s-local
{{< /highlight >}}

And now if we check our contexts, we should see this:

{{< highlight sh >}}
$ kubectl config get-contexts
CURRENT   NAME        CLUSTER     AUTHINFO   NAMESPACE
          cluster-1   cluster-1   default    
*         k3s-local   k3s-local   default     
{{< /highlight >}}

<h4>Which kubectl?</h4>

You may have more than one `kubectl` available.

Using `k3s kubectl` over `kubectl` shouldn’t make a difference as long as you set your Kubernetes config properly.

The following commands are equivalent:

{{< highlight sh >}}
$ KUBECONFIG=~/.kube/config-k3s kubectl get nodes
$ kubectl get nodes --kubeconfig=~/.kube/config-k3s
$ sudo k3s kubectl get nodes
{{< /highlight >}}

### Command completion

It is extremely handy to have command completion available for `kubectl` since the commands tend to get pretty verbose. If your package manager didn't install completion alongside `kubectl`, you can install it manually by 

{{< highlight sh >}}
$ kubectl completion bash | sudo tee /usr/share/bash-completion/completions/kubectl
$ source ~/.bashrc
{{< /highlight >}}

Also, it’s tiring to type `kubectl` repeatedly, so let’s alias it to `kl`, and make sure completions are loaded for the alias too. 
Add these lines to your `~/.bash_aliases`:

{{< highlight sh >}}
alias kl=kubectl
type -f __start_kubectl 2>&amp;- || _completion_loader kubectl
complete -o default -o nospace -F __start_kubectl kl
{{< /highlight >}}

**NOTE:** On Ubuntu 16.04 right on up through 20.04, bash completion is disabled by default system-wide. So let’s make sure it's installed and enabled:

{{< highlight sh >}}
$ sudo apt -y install bash-completion
$ sudo sed -i.bak -E '/if ! shopt -oq posix; then/,+6 s/^#//g' /etc/bash.bashrc
{{< /highlight >}}

Make sure to restart your shell for changes to take effect.

<!-- wp:separator -->
<hr class="wp-block-separator"/>
<!-- /wp:separator -->

## Running a Container

Run a container inside your cluster:

{{< highlight sh >}}
$ kubectl run -it ubuntu --image=ubuntu:bionic -- bash
{{< /highlight >}}

If you've used Docker before, you'll appreciate the similarity to the `docker run` syntax.

This does a few things behind the scenes:

* Create a `Pod` named `ubuntu` running a single container
* Pull the image `ubuntu:bionic` from the public Docker registry
* Drop an interactive shell into the container

You can poke around, install some packages, take a look at `/etc/resolv.conf`, maybe take a look at the running environment with `env`, or `mount`, or `top`.

When you are done, exit the shell. This will terminate the pod.

Note, however, that Kubernetes will create a new pod in its place. This can be confirmed by running `kubectl get pods`:

{{< highlight sh >}}
NAME      READY   STATUS    RESTARTS   AGE
ubuntu    1/1     Running   1          75s
{{< /highlight >}}

To get rid of the pod for good, run:

{{< highlight sh >}}
$ kubectl delete pod ubuntu
{{< /highlight >}}

## Configuration as Code

One of the real superpowers of Kubernetes, in my opinion, is the ability to do almost anything either completely imperatively ("do this! do that! then do these three things!") or declaratively ("here's what I want it to look like at the end - _you_ figure out how to get there").

Let's take our imperative `kubectl run` example from above, and generate a declarative manifest from it that we can save to a file and, say, commit to version control: 

{{< highlight sh >}}
$ kubectl run ubuntu --image=ubuntu:bionic --dry-run=client --output yaml > pod.yaml
{{< /highlight >}}

What you'll get back instead of a shell prompt inside your container is the instructions for building your deployment in YAML form, which you can then modify as needed, and then apply with `kubectl apply -f pod.yaml`.

---

# Helm

What would Linux be without `apt`? Helm is the `apt` of Kubernetes, and more. It uses charts, which are like package manifests, to instantiate and manage Kubernetes objects such as deployments, secrets, and configMaps as a unified, versioned set called a release. It can template values using the Go templating language, `gotpl`. It can roll back releases to previous versions. It can... well, you get it.

## Installation

Helm can  be installed on all supported OSes with:

{{< highlight sh >}}
$ curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
{{< /highlight >}}

Install Helm bash completion:

{{< highlight sh >}}
$ helm completion bash | sudo tee /usr/share/bash-completion/completions/helm
$ source ~/.bashrc
{{< /highlight >}}

## Example: Install Grafana

Let’s test our local Kubernetes cluster by installing a relatively straightforward Helm chart, Grafana.

First, let's add the Helm stable chart repository:

{{< highlight sh >}}
$ helm repo add stable https://kubernetes-charts.storage.googleapis.com
$ helm repo update
{{< /highlight >}}

{{< highlight sh >}}
$ helm install grafana stable/grafana
{{< /highlight >}}

After a few moments you should see some output describing the Kubernetes objects created that make up the release, as well as some notes about next steps. Following these notes, retrieve the auto-generated admin password:

{{< highlight sh >}}
$ kubectl get secret --namespace default grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
{{< /highlight >}}

Since the Grafana chart deploys a service of type `ClusterIP` by default with no ingress to route traffic to the cluster from outside, we have to use port forwarding to access the pod.

Think of port forwarding as the `ssh -L` of Kubernetes - it abstracts away all the complex networking stuff happening under the hood (and there's a lot of it) to give you access to your services through the control plane, like this:

{{< highlight sh >}}
$ export POD_NAME=$(kubectl get pods --namespace default -l "app=grafana,release=grafana" -o jsonpath="{.items[0].metadata.name}")
$ kubectl --namespace default port-forward $POD_NAME 3000
{{< /highlight >}}

Note that if you installed `kubectl` bash completion, the generated pod name will be available as a completion in an interactive shell.

Now we can access Grafana at `http://localhost:3000`, just as if we had deployed Grafana to a remote server and logged in to it with `ssh -L`.

### Getting Info

Let's get some more info about our Grafana deployment.

Every Kubernetes object has as part of its metadata a set of key-value pairs called labels. We can perform operations on multiple objects at a time using label selectors. An example of this can be seen above in the port forwarding command - specifically the `-l app=grafana,release=grafana` part. This is useful if, for example, you have two versions of the same app deployed simultaneously, and you want to differentiate between two sets of objects by release.

Most Helm charts provide a label called `release` with the name of the release as the value. The Grafana chart is no exception.

So let's get a list of all objects matching this label selector:

{{< highlight sh >}}
$ kl get all -l app=grafana,release=grafana
{{< /highlight >}}

You should get back something like this:

{{< highlight sh >}}
NAME                          READY   STATUS    RESTARTS   AGE
pod/grafana-6c6d9cfd6-4fhnn   1/1     Running   0          2m18s

NAME              TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/grafana   ClusterIP   10.43.184.148   <none>        80/TCP    2m18s

NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/grafana   1/1     1            1           2m18s

NAME                                DESIRED   CURRENT   READY   AGE
replicaset.apps/grafana-6c6d9cfd6   1         1         1       2m18s
{{< /highlight >}}

`kubectl` also supports different output formats like YAML, JSON, and even `jsonpath` which can extract specific fields from the manifest to be used programmatically. [[7](https://kubernetes.io/docs/reference/kubectl/jsonpath/)]

For example, to get the `ClusterIP` address for the Grafana service from above to be used in a script:

{{< highlight sh >}}
$ kubectl get svc -l app=grafana,release=grafana \
  -o jsonpath='{.items[0].spec.clusterIP}'
10.43.184.148
{{< /highlight >}}

A more complicated example which gets the port number for a port named `service`:

{{< highlight sh >}}
$ kubectl get svc -l app=grafana,release=grafana \
  -ojsonpath='{.items[*].spec.ports[?(@.name=="service")].port}'
80
{{< /highlight >}}

Here's the equivalent in `jq`, which some may feel a little more at home with (I know I do):

{{< highlight sh >}}
$ kubectl get svc -l app=grafana,release=grafana -ojson \
  | jq '.items[].spec.ports[] | select(.name=="service").port'
80
{{< /highlight >}}

When done testing, we can delete the release and make it like it never existed with

{{< highlight sh >}}
$ helm delete grafana
{{< /highlight >}}

When all else fails:

{{< highlight sh >}}
$ kubectl cluster-info dump
{{< /highlight >}}

---

## Using a Private Registry

You might be working on a project the world isn't yet ready for, in which case you're probably using a private container registry that requires credentials. If we want to use a container image hosted on a private registry like [gcr.io](http://gcr.io/), we need to tell `k3s` how to authenticate. In GKE this would normally just work, but since we're not running in Google's walled garden we have to specify an `ImagePullSecret`.

First we need to create a service account key with read-only access to Google Cloud Storage, which Google Container Registry uses as its backend:

{{< highlight sh >}}
$ gcloud iam service-accounts keys create \
  --iam-account=gcr-readonly@<your_project_id>.iam.gserviceaccount.com \
  gcr-readonly.json
{{< /highlight >}}

Create a Kubernetes secret of type `docker-registry` from the service account key. 

We are going to call our secret `gcr-readonly-secret`:

{{< highlight sh >}}
$ kubectl create secret docker-registry gcr-readonly-secret \
  --docker-server=https://gcr.io \
  --docker-username=_json_key \
  --docker-password="$(cat gcr-readonly.json)"
{{< /highlight >}}

Now we can do one of two things: a) Specify an `imagePullSecret` for every deployment that needs to pull images from this registry, or b) patch our default service account to include a reference to our image pull secret. We're going to go with option B to keep our manifests [DRY](https://en.wikipedia.org/wiki/Don%27t_repeat_yourself):

{{< highlight sh >}}
$ kubectl patch serviceaccount default -p \
'{"imagePullSecrets": [{"name": "gcr-readonly-secret"}]}'
{{< /highlight >}}

Although not strictly necessary, we also want to create a generic secret with this service account key to be used by pods themselves to interact with GCS:

{{< highlight sh >}}
$ kubectl create secret generic gcs-service-account-key --from-file=gcr-readonly.json
{{< /highlight >}}

Now we can create pods and deployments from images in our private container registry, `gcr.io/<your_project_id>` and `k3s` will be able to pull them.

For the sake of brevity I'm leaving out some of the GCP-specific steps of interacting with a private registry, but the overall development process would go something like:

* write a Dockerfile for your code and its dependencies
* build a container with 
{{< highlight sh >}}
docker build -t gcr.io/<your_project_id>/super-cool-app:0.0.1
{{< /highlight >}}
* push it to your registry with 
{{< highlight sh >}}
docker push gcr.io/<your_project_id>/super-cool-app:0.0.1
{{< /highlight >}}
* write some Kubernetes manifests (or even your very own Helm chart!) to deploy your app

And that's it, folks.

Obviously there is a _whole lot_ more to Kubernetes, but I hope this guide helps you get your feet wet.

Please leave a comment and let me know if you found this useful!

---

## References

1. https://medium.com/@marcovillarreal_40011/cheap-and-local-kubernetes-playground-with-k3s-helm-5a0e2a110de9
1. https://helm.sh/docs/intro/install/
1. https://ahmet.im/blog/mastering-kubeconfig/
1. https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/
1. https://kubernetes.io/docs/reference/kubectl/jsonpath/
1. https://rancher.com/docs/k3s/latest/en/configuration
