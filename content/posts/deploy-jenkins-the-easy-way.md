---
author: "oofnik"
title: "deploy jenkins the easy way"
summary: |
  Jenkins will probably never go away. It's an absolute beast of a software package, both in terms of capabilities, as well as headache - inducing power.
tags: 
  - "gitops"
  - "helm"
  - "jenkins"
  - "kubernetes"
date: 2020-08-02
draft: false
---

Jenkins will probably never go away. It's an absolute beast of a software package, both in terms of capabilities, as well as headache - inducing power. At least modern DevOps tools make it easier than ever to get up and running.

## Can - Do Dinosaur

Jenkins has been around in some form or another for more than fifteen years. It's the unsung mule of the software industry: handling everything from continuous integration, deployment automation, scheduled tasks, even manually configured one-off jobs, it's become the do-everything tool that every software dev team has at least wrestled with, and probably more than once.

Since its original debut in 2005 under the name Hudson, the software world has become a very, very different place. Jenkins (Hudson) was architected, like many software platforms of the day, as a giant Java monolith. Looking back from today's containerized and serverless applications running on distributed cloud infrastructure, it's rather amusing that such a dinosaur is still powering critical production stuff for so many companies.

Why would _anybody_ choose something like Jenkins in 2020 over today's [proliferation](https://about.gitlab.com/stages-devops-lifecycle/continuous-integration/) [of](https://github.com/features/actions) [alternative](https://circleci.com/docs/2.0/about-circleci/) [continuous](https://docs.drone.io/) [integration](https://docs.travis-ci.com/user/for-beginners/) [and](https://cloud.google.com/cloud-build) [delivery](https://aws.amazon.com/codebuild/) software platforms? The answer, I think, is simply this:

**Short of automating a SpaceX launch, there is probably nothing Jenkins can't do.**

Any of the CI/CD platforms on the market today can handle SCM triggering, automated testing, and packaging and deploying of artifacts. But veering even a little bit off that beaten path with anything other than Jenkins will quickly turn into a long evening of what is very likely to result in futility.

A brief list of non - CI/CD things I've automated with Jenkins:

- spin up and tear down test environments on demand to test feature branches
- delete orphaned or abandoned cloud resources on a schedule and generate a report
- database migration between geographic regions
- generate user credentials for some service and e-mail them to whoever ran the job
- provision new infrastructure with interactive approval by specific team members

I'm all for modernizing, but there are some tools for which there is currently no adequate replacement.

* * *

With that said, there have been _tremendous_ improvements in the Jenkins ecosystem lately with regard to deployment. The advantages of declarative configuration have finally transformed what was once an hours-long process of installing and configuring a Jenkins server into a set of manifests that can be version controlled and deployed as in any other modern GitOps flow.

I've put together a [repository](https://github.com/oofnikj/jenkins-easy) to showcase how modern tooling can be used to deploy a Jenkins instance on Kubernetes in a 100% declarative fashion. With the help of two plugins in particular, [Jenkins Configuration as Code](https://github.com/jenkinsci/configuration-as-code-plugin) and [Job DSL](https://github.com/jenkinsci/job-dsl-plugin), the horrid mess of Jenkins configuration can be abstracted into a repeatable workflow that doesn't require clicking around in a UI from the early 2000's, running carefully crafted commands in a particular order, or (heaven forbid) modifying XML files on disk and hoping you didn't forget a forward slash somewhere.

### The parts

The Jenkins deployment itself is orchestrated by the [FluxCD Helm operator](https://docs.fluxcd.io/projects/helm-operator/en/stable/). If you're not familiar with Kubernetes operators, an operator is a piece of software that watches for changes in a particular kind of custom resource on a cluster - say, a `HelmRelease` - and does the things it needs to do in order to bring the state of the system in line with the declaration, extending the logic of the Kubernetes control plane to basically anything in the cluster.

There is, in fact, a [Jenkins operator](https://jenkinsci.github.io/kubernetes-operator/docs/), which I've played with, and while it looks promising, I ran into a few issues with customization that I think need a little more polishing. Perhaps in the future, those issues will be ironed out and I'll migrate this guide to using it, but meanwhile, I'm relying on the relatively battle-tested [Jenkins Helm chart](https://github.com/helm/charts/tree/master/stable/jenkins).

The Jenkins Helm chart handles the installation of plugins and placement of configuration files. Once the main Jenkins server is running, JCasC kicks in and configures things like the security realm and credential provisioning. Finally, Job DSL is used to create a seed job which, when run, will download all the job definitions from the same Git repository holding the rest of the configuration and provision your Jenkins jobs accordingly.

Identity is managed by an external provider. I chose Okta because they have an easy to use API, great documentation, and a dev account is free. Most importantly, Okta resources can be provisioned with Terraform, which brings us closer to our goal of being completely declarative.

All the code, including step-by-step instructions and references, is available on GitHub: [https://github.com/oofnikj/jenkins-easy](https://github.com/oofnikj/jenkins-easy)

* * *

### References

Shout out to Gregory Paciga over at [gerg.dev](https://gerg.dev/2020/06/creating-a-job-dsl-seed-job-with-jcasc/) for the seed job inspiration. The docs are a bit lacking on this topic.

- Job DSL Wiki [https://github.com/jenkinsci/job-dsl-plugin/wiki](https://github.com/jenkinsci/job-dsl-plugin/wikihttps://github.com/jenkinsci/configuration-as-code-pluginhttps://gerg.dev/2020/06/creating-a-job-dsl-seed-job-with-jcasc/https://docs.fluxcd.io/projects/helm-operator/en/stable/get-started/using-helm/https://developer.okta.com/blog/2019/10/21/illustrated-guide-to-oauth-and-oidchttps://www.terraform.io/docs/providers/okta/index.html)
- JCasC plugin [https://github.com/jenkinsci/configuration-as-code-plugin](https://github.com/jenkinsci/configuration-as-code-plugin)
- Jenkins Helm chart [https://github.com/jenkinsci/helm-charts](https://github.com/jenkinsci/helm-charts)
- Gregory's blog post [https://gerg.dev/2020/06/creating-a-job-dsl-seed-job-with-jcasc/](https://gerg.dev/2020/06/creating-a-job-dsl-seed-job-with-jcasc/)
- FluxCD Helm Operator [https://docs.fluxcd.io/projects/helm-operator/en/stable/get-started/using-helm/](https://docs.fluxcd.io/projects/helm-operator/en/stable/get-started/using-helm/)
- Okta guide to OAuth2 and OpenID Connect [https://developer.okta.com/blog/2019/10/21/illustrated-guide-to-oauth-and-oidc](https://developer.okta.com/blog/2019/10/21/illustrated-guide-to-oauth-and-oidc)
- Okta Terraform provider docs [https://www.terraform.io/docs/providers/okta/index.html](https://www.terraform.io/docs/providers/okta/index.html)
