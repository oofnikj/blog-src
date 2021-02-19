---
author: "oofnik"
title: "ship azure application gateway logs to datadog"
summary: |
  Azure doesn't make it particularly easy to integrate with external logging and metrics providers. Here's one way to do it.
tags:
  - azure
  - datadog
  - serverless
date: 2021-02-19T14:29:00+02:00
draft: false
---

Since building out our cloud infrastructure exclusively on AWS for several years, our company recently started delving into Azure. Besides being a great learning experience, it's always good to understand and be familiar with how the basic building blocks of the cloud (compute, storage, permissions, observability) are implemented across providers.

Even if you build your product to run on an industry standard platform, the state of the cloud is such that differences in implementation can have a significant impact on migration efforts. Infrastructure-as-code solutions are not cloud agnostic; a complete rewrite of all your module and environment code is usually necessary. In short, it's more than just running `sed -i 's/aws/azure/g'` on your code base.

With that said, there are obvious advantages to be had by aiming for standards compliance - even if the code is different, the same deployment tools and practices are still applicable whether you're deploying to AWS, Azure, or GCP. By factoring the infrastructure stuff out from the business logic, development teams can focus on writing good, secure code without worrying too much over how or where (or even whether) it will run.

## The Stack

I'm going to focus here on the fourth building block - observability - and how I built a log delivery pipeline on Azure to complement the one we had already built with AWS.

Both cloud providers offer a variety of managed load balancer solutions. On AWS, we're using Application Load Balancer to front our workload running on EKS. The load balancers log all traffic to an S3 storage bucket. Those log writes trigger a Lambda function which parses and forwards the logs to Datadog.

In Azure land, Azure Application Gateway forwards traffic to our workload running on AKS. The Application Gateway is configured through a diagnostic setting to write logs to Azure blob storage. An Azure Function App is triggered by the logs and, once again, forwards the logs to Datadog. The end result, for either cloud, is the same. But more importantly, both of these pipelines are deployed using the same tools, from the same VCS repository.

Thankfully, Datadog provides [serverless code](https://github.com/DataDog/datadog-serverless-functions) for both AWS and Azure. But the documentation is a bit thin on how to actually go about deploying it.

## Azure Functions

A lot has been written about serverless architectures, but one of the biggest pitfalls I've encountered with every single serverless platform I've had the misfortune of touching is the amount of voodoo necessary to actually get serverless code running.

Also, in every case, that voodoo looks _completely different_. 

It might be simply because serverless hasn't had time to coalesce around a standard way of doing things like other more mature orchestration frameworks have had. But as of early 2021, every time I encounter something serverless, I can't shake the feeling that the whole thing is held together with duct tape and crossed fingers.

But anyway.

I followed the [Azure Quickstart](https://docs.microsoft.com/en-us/azure/azure-functions/create-first-function-cli-node?tabs=azure-cli%2Cbrowser) to get a feel for how to create a new serverless deployment using their CLI tool. Creating a new JavaScript function generates a `function.json` file which, among other things, defines how that function is triggered. Datadog [provides](https://github.com/DataDog/datadog-serverless-functions/tree/master/azure/blobs_logs_monitoring) a sample `function.json` with their Azure serverless code, but I had to do a lot of extra reading to understand what's going on behind the scenes. Perhaps most confusing is the `bindings.connection` entry; [Apparently](https://docs.microsoft.com/en-us/azure/azure-functions/functions-bindings-storage-blob-trigger?tabs=javascript#configuration), by leaving this blank, as long as you've configured your application settings properly (which we'll do in the deployment section below), your blob storage-triggered function will _just work_. Okay. Magic voodoo.

* * *

Once everything is set up properly, you should have a set of files that looks like this:

```shell
.
├── function
│   ├── datadog_logs_monitoring
│   │   ├── function.json
│   │   └── index.js
│   ├── host.json
│   └── local.settings.json
└── ...
```

The first two files are from the Datadog repo linked above. `host.json` is the Azure serverless manifest for the multi-function app that got generated from the Azure quickstart guide. `local.settings.json` is optional here; it gets ignored on deploy as you'll see soon.

From the `function` directory, you can actually go ahead and deploy the function to Azure using the CLI tool, but we're going to one up that and do it all in Terraform.

## Deployment

The rest of this post is heavily borrowed from [Adrian Hall](https://adrianhall.github.io/typescript/2019/10/23/terraform-functions/)'s excellent write-up on deploying an Azure Function App with Terraform. I think it says something about the Azure docs that a personal blog post by a Microsoft employee was my primary reference for how to do this, but I digress.

The basic idea is this: Use Terraform to setup the Azure App Function infrastructure along with all of the requisite parts. Then, using the `archive` provider, package the code into a `zip` file, upload it to blob storage, and ... duct tape and crossed fingers.

Inputs:
- `prefix`: resource name prefix
- `resource_group_name`: name of the resource group where your Application Gateway is deployed
- `azurerm_application_gateway_id`: ID of the App Gateway
- `storage_account_name`: name of a storage account where App Gateway logs and function code will be uploaded to
- `datadog_api_key`: Datadog API key

{{< highlight hcl "linenos=table" >}}
{{< include "static/ship-azure-application-gateway-logs-to-datadog/main.tf" >}}
{{< /highlight >}}


The only essential part that remains is to configure Datadog to properly grok the timestamp field from the logs. This can be done by defining a new log pipeline with a filter like `source:azure-application-gateway`, and adding a date remapper to pull the timestamp from the `timeStamp` field. There are a couple of other handy processors available to parse things like HTTP status codes that I recommend using as well.

---
# Resources
1. https://github.com/DataDog/datadog-serverless-functions
1. https://itnext.io/datadog-azure-api-management-logs-60f9d45d667a
1. https://adrianhall.github.io/typescript/2019/10/23/terraform-functions/
1. https://docs.microsoft.com/en-us/azure/azure-functions/
1. https://docs.microsoft.com/en-us/azure/azure-functions/create-first-function-cli-node?tabs=azure-cli%2Cbrowser
1. https://docs.microsoft.com/en-us/azure/azure-functions/functions-bindings-storage-blob-trigger?tabs=javascript#configuration