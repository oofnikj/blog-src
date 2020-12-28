---
author: "oofnik"
title: "breaking down AWS flow logs"
summary: |
  Extract detailed cost information from network flow logs and present it in an interactive dashboard.
tags: 
  - "athena"
  - "aws"
  - "nat"
  - "networking"
  - "sql"
date: 2020-05-23
draft: false
---

In this post I'll cover the journey we took to extract detailed cost information from network flow logs and present it in an interactive dashboard.

## Motivation

The AWS pricing model can be roughly divided into two types of expenses: time and data. Some managed resources, like EC2 instances or RDS databases, are very up-front about these costs, which you can quickly and easily estimate using the [AWS Pricing Calculator.](https://calculator.aws/#/)

But most production deployments are composed of a long list of discrete resource types - databases, serverless functions, compute instances, and all the interconnected networking, monitoring, and failover bits and pieces in between. Trying to accurately estimate and plan the cost of a complex system can become as challenging a task as building that system in the first place.

There are even [costs associated with assessing costs](https://aws.amazon.com/aws-cost-management/pricing/), and [entire companies](https://www.cloudvisor.io/) dedicated to helping you manage those costs as an external service.

* * *

What if your deployments are partially multi-tenant? What if you want a cost breakdown per customer, for example, and you've got separate databases per customer, but all of your data is flowing through the same set of load balancers? Cost analysis becomes a non-trivial problem.

In my company's case, we have several hundred VPCs scattered across a few dozen AWS accounts that are all interconnected using AWS Transit Gateway, a managed layer 3 routing service that allows for building out a multi-region, multi-cloud network in a scalable way. For our internal services that need internet access, we previously used to deploy a managed NAT gateway in each VPC that required one. Managed NAT gateways cost both per hour and per gigabyte of traffic processed, and they were getting expensive. Since we already had connectivity between VPCs provided by the transit gateways, we consolidated the NAT gateways into a single "egress VPC" per stage, vastly reducing our hourly cost.

But there was one problem - by consolidating the NAT gateways, we lost the ability to break down NAT costs per account, which we needed in order to go after the data cost. Several terabytes of egress traffic a day and no visibility into where it's coming from or where it's going is, by all measures, not good.

There are external auditing services who, for a sizable chunk of money, will continuously analyze your network logs and provide a breakdown of what's flowing where, and whether there are any anomalies indicating a potential security issue.

In addition to the cost of the analysis, such solutions also require you to a) collect the logs in the first place, and b) ship those logs out to an external service.

Instead, we opted to build something quick and in-house that would restore some of the visibility we had prior to the consolidation.

* * *

## Flow Logs

AWS Flow Logs, when enabled on a network interface, provide a line-by-line aggregation of every byte going into or coming out of that interface. The logs can be queried directly in CloudWatch or, for more extensive analysis, dumped to an S3 bucket in tabular format. AWS provides [documentation](https://docs.aws.amazon.com/athena/latest/ug/vpc-flow-logs.html) on how to query flow logs with Athena, which was helpful for getting us started, but there are plenty of other tools that can do the job.

A standard set of fields is provided, including source and destination address, bytes transferred, and timestamp, but there are some [additional fields](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html#flow-logs-fields) we'll need to include in order to analyze NAT traffic.

A typical flow log entry might look like this:

```csv
srcaddr dstaddr pkt-srcaddr pkt-dstaddr srcport dstport bytes tcp-flags start log-status account-id interface-id protocol packets action end
10.10.52.25 10.10.10.1 10.10.52.25 188.24.16.5 443 14365 9804 0 1590015808 OK 111111111111 eni-0ad2cbc46f103cb9a 6 76 ACCEPT 1590015928
```

We're interested in a couple of things here. First of all, it's important to note that flow logs will always show the internal IP address of an interface in the `srcaddr` and `dstaddr` fields, even if the packet arrives on an external address. Since we're analyzing NAT traffic, we need to include the additional packet and source destination address fields.

Also, the `account-id` field isn't the account ID of the packet origin -- it's just the account ID of the NAT gateway to which the interface is attached.

Perhaps more confusing is the fact that an AWS-managed NAT gateway only has one network interface. This means that every entry in the flow log for this particular interface will (hopefully) have a second entry with an identical byte count, same ENI ID, same timestamps, but a different set of IP addresses - first from the source to the NAT gateway, and second from the NAT gateway to the external destination.

{{< figure src=images/flowlogs.png caption="color-coded matching flow log entries for a NAT gateway" >}}

If we were to sum all the values in the `bytes` column and multiply by the data cost for the region in which our NAT gateway was deployed, we'd arrive at a number that was roughly twice the value observed in our monthly billing report.

What's critical to note here is that _charges are only incurred_ _for data flowing into and out of your VPC._ Traffic flowing from other things in your VPC to the NAT gateway, while clearly visible in the logs, are not charged. So we need to do some filtering. And for that, we need to understand what the NAT gateway is really doing.

NAT, short for Network Address Translation, does exactly what the name indicates: a NAT gateway proxies IP traffic between an internal address on your network and an external destination, keeping track of the outgoing connections so it knows where to send any incoming responses that might return. It gets a lot more [complicated](https://en.wikipedia.org/wiki/Network_address_translation) than that, but that's the general idea.

Knowing this, we can select only for the rows of flow log data in which NAT actually occurs - in other words, the rows that cost us money.

Using SQL, that would look something like this:

```sql
SELECT * FROM flow_logs
WHERE dstaddr != pkt_dstaddr
OR srcaddr != pkt_srcaddr
```

Only the first line in the above set of matching flow log entries would match our `WHERE` criteria - that's the only row in which we're interested, since it captures information about who sent the packet (`srcaddr` - the source), who received it (`dstaddr` - the NAT gateway), and the packet's final destination (`pkt-dstaddr`). For traffic flowing back through the gateway, we'd be interested in `pkt-srcaddr` to know where that packet really came from.

It should be noted that technically, we're being charged for the _second_ row, not the first one. But the first row contains the information we want, and since the byte count is identical (two sides of the same flow), that's the line we'll focus on.

With that logic, we can build some more complex queries.

Here's an example that will show us the top 10 source - destination pairs of traffic flow, ordered by total bytes (not actual IPs!):

```sql
SELECT pkt_srcaddr, pkt_dstaddr, sum(bytes) 
FROM flow_logs 
WHERE pkt_srcaddr != srcaddr 
  OR pkt_dstaddr != dstaddr 
GROUP BY 1,2 ORDER BY 3 DESC LIMIT 10;
```

    pkt_srcaddr    pkt_dstaddr    sum(bytes)
    54.219.93.112  10.10.25.13    89446
    10.10.25.13    54.219.93.112  40328
    10.10.4.77     52.7.244.157   34809
    52.49.154.124  10.10.25.13    34386
    54.239.18.135  10.10.25.13    27384
    10.10.179.51   62.28.14.94    27292
    52.94.242.20   10.162.3.183   22689
    54.239.17.195  10.10.25.13    20574
    54.27.121.30   10.10.99.116   19745
    10.10.57.98    52.19.196.69   18743

Notice how the IP address of our NAT gateway is nowhere to be found in this table. The logic checks out - we're filtering out all the middle-man traffic, leaving only the true source and destination. Furthermore, cross-checking our byte sums against the AWS Cost Explorer gave us a margin of error of 0.1%.

* * *

## Summary

Using this technique, we built a comprehensive dashboard that shows a breakdown of network costs per team. We discovered several data-hungry services making requests over the internet instead of through VPC endpoints due to misconfigured route tables, allowing us to significantly reduce costs.

Not only have we restored the visibility we had prior to the NAT consolidation project but we've added significant value by enriching the raw flow log data with detailed information about the private addresses in our network from our IPAM backend (we're using [NetBox](https://github.com/netbox-community/netbox)), and the public addresses published by [AWS](https://docs.aws.amazon.com/general/latest/gr/aws-ip-ranges.html) for their managed services.
