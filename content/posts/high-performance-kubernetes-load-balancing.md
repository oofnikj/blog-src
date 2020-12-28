---
author: "oofnik"
title: "high performance kubernetes load balancing"
summary: |
  What began as an investigation into a very stubborn intermittent error turned into a write-up on how to squeeze the most out of your Kubernetes deployment.
tags:
  - HAProxy
  - iptables
  - kubernetes
  - Traefik
  - uWSGI
date: 2019-10-03T05:48:40+00:00
draft: false
---

What began as an investigation into a very stubborn intermittent error turned into a write-up on how to squeeze the most out of your Kubernetes deployment.

* * * 

Among the many features of Kubernetes, perhaps one of the most useful (and innovative) is its use of IP tables to perform the gruntwork of network plumbing. 

If you haven't already, I highly recommend watching Michael Rubin and Tim Hockin discuss the [ins and outs of Kubernetes networking](https://www.youtube.com/watch?v=y2bhV81MfKQ). It's a great overview of the k8s networking layer with a lot of examples and step-by-step explanation.

## Background

First, a little background. My company offers a product that enhances e-commerce search by running a store's online catalog and query stream through a natural language engine to improve recall and precision for end users. 

The product is exposed as a a two-part API: queries and listings. A store's product catalog must first be indexed through our API, which analyzes existing data fields like title and description, adding structured data according to the product type - sizes and colors for fashion, freshness for grocery items, etc. These items get indexed back in to a search engine on the customer side. End-user queries are then analyzed in real-time with the same engine and translated into search engine-speak to return matching items from the indexed catalog.

The takeaway here is high throughput for the listings API, while the goal for the queries API is low latency.

Over the last few months, we've put a lot of work into bringing our infrastructure up to date by preparing a migration from compute instances to an orchestrated containerized platform.

You can probably guess which one.

I'm going to focus on the listings API in this post. Perhaps I'll go into the queries API in the future, but for now that'll remain out of scope.

---

### The Old

The classic deployment looks like this: A fixed number of worker processes (let's say 4) are distributed among a set of autoscaling instances (for example, 10). These instances sit behind an HAProxy load balancer, which is itself stationed behind a cloud load balancer to handle SSL termination. 

All except for one of the worker instances are switched off when there are no indexing requests. HAProxy configuration is dynamically updated with the number of workers online through Consul template, so it knows how many connections it can accept before returning errors.

Most of the time, HAProxy is idling along, ready to accept a maximum of 4 connections (4 workers per node x 1 online node) when requests start blasting in at full speed (40 concurrent). 
At this point HAProxy returns status `429` to the client until the rest of the instances have time to scale up. Scaling is handled by a custom script that reads the `429` rate from the HAProxy stats endpoint and determines how many instances needed to be brought online to handle the demand. This process ideally takes 2-3 minutes, after which the `429` rate drops to zero.

### The New

While re-implementing the logic in Kubernetes, we did away with the custom autoscaling stuff, relying instead on GKE's autoscaling node pool plus a `HorizontalPodAutoscaler` to scale the deployment as needed.

For testing, I settled on an intermediate-sized cluster of 6 nodes, 4 vCPUs each, for a total of 24 workers, one process per CPU core. No multi-threading here.

#### IP Tables

At first, I tried round-robin load balancing using the virtual IP created by a `ClusterIP` service, leaving out the HAProxy bits altogether. This worked, even error-free, only it was about two-thirds slower than the classic deployment. So that wasn't going to fly. 

Switching to the use of `NodePort`, setting `externalTrafficPolicy` to either `Local` or `Cluster` made things even worse:

| LB Type             | Response Time (ms), mean | Requests / sec, mean |
|         ---         |           ---            |         ---          |
| ClusterIP           | 732                      | 32.8                 |
| NodePort (Local)    | 912                      | 26.3                 |
| NodePort (Cluster)  | 944                      | 25.4                 |

My best guess is that because IP tables operates in kernel space, there's a lot of context-switching going on, causing a huge slowdown in processing speed. Looking at `top` on one of the indexing nodes revealed that a good chunk of CPU time was spent idling, reinforcing my suspicion:

    %Cpu(s): 49.1 us,  2.8 sy,  0.0 ni, 47.9 id,  0.0 wa,  0.0 hi,  0.2 si,  0.0 st

My next attempt involved deploying an ingress controller to handle load balancing at the application layer.

#### Layer 7 - Traefik

Since I'd read a lot about [Traefik](https://traefik.io/) and played around with it while writing my [local Kubernetes development guide](https://badgateway.qc.to/local-development-with-kubernetes/), I decided to give it a try.

First, I wrote an `Ingress` object to be picked up by the Traefik controller. Then, per the [docs](https://docs.traefik.io/v1.7/configuration/backends/kubernetes/#annotations), I had to add some annotations to my app's service definition to limit the maximum number of connections:

```yaml
...
metadata:
  annotations:
    traefik.ingress.kubernetes.io/max-conn-amount: "24"
    traefik.ingress.kubernetes.io/max-conn-extractor-func: client.ip
...
```

Hammering it with `ab` with the same command-line options as before:

```sh
$ ab -t300 -c24 -k -r -l -p listing.json -T 'application/json' -m post \ 
  http://haproxy-controller.kube-system/listings
```

A quick note about the command line flags used here for those of you who don't feel like pulling up the `man` page:

* `-t300`: run for 5 minutes
* `-c24`: 24 concurrent connections
* `-k`: add a HTTP keep-alive header. `ab` speaks `HTTP/1.0`, which defaults to no keepalive.
* `-r`: ignore errors
* `-l`: accept variable length responses. Our app returns a request ID which is randomly generated and not always the same length.
* `-p ...`: POST a file, and
* `-T 'application/json'`: send it as JSON

And here's where the intermittent error begins to appear. 

While load testing the listings API with Traefik, I encountered a consistent error rate of about 0.8 - 1% from the client side. The client would occasionally receive either `500` or `502` from the load balancer (hello, [blog name](https://http.cat/502)) at seemingly random intervals. I tested with our internal indexing client, with `jmeter`, with `ab`, and with `curl` running in a `while` loop (yes, really), all showing the same results. The classic deployment didn't do that.

When you're aiming for an SLA of five 9's, that is a no-go. 

Here's what `ab` reports:

{{< highlight sh "hl_lines=5 10 11" >}}
Concurrency Level:      24
Time taken for tests:   300.004 seconds
Complete requests:      14217
Failed requests:        0
Non-2xx responses:      67
Keep-Alive requests:    14217
Total transferred:      16672816 bytes
Total body sent:        31315959
HTML transferred:       12557455 bytes
Requests per second:    47.39 [#/sec] (mean)
Time per request:       506.442 [ms] (mean)
Time per request:       21.102 [ms] (mean, across all concurrent requests)
Transfer rate:          54.27 [Kbytes/sec] received
                        101.94 kb/s sent
                        156.21 kb/s total
{{< /highlight >}}

Okay. On one hand, we're getting a _~30%_ increase in throughput by balancing with an ingress controller instead of IP tables. So that's good. But on the other hand, we're getting errors. Not a whole lot of them, but still not satisfactory for our SLA with our customers. 

What's going on here?

I did some research - mostly googling around, but also examining a `tcpdump` of a load testing session, which confirmed that the non-2xx responses above were indeed mostly `502`'s - and found an open [bug report](https://github.com/containous/traefik/issues/3237) in the Traefik project on GitHub that seems to match my experience, with a lot of suggested workarounds.

The one that eventually did the trick, as counter-intuitive as it may seem, was to [disable keepalives](https://github.com/containous/traefik/issues/3237#issuecomment-514178590) in the Traefik configuration.

Since the author of the comment on the bug report that saved the day already linked to the relevant library used by Traefik, I perused some more and found this [tidbit](https://github.com/golang/go/blob/release-branch.go1.12/src/net/http/transport.go#L71-L74):

{{< highlight go "linenos=inline, linenostart=71" >}}
// By default, Transport caches connections for future re-use.
// This may leave many open connections when accessing many hosts.
// This behavior can be managed using Transport's CloseIdleConnections method
// and the MaxIdleConnsPerHost and DisableKeepAlives fields.
{{< /highlight >}}

Apparently, connection caching does not play nice with uWSGI, which we also happen to be using as our application server.

Testing again after setting `MaxIdleConnsPerHost = -1` in the Traefik config yielded similar performance, but with zero errors. Great success!

Let's see if we can push things even further. 

#### Layer 7 - HAProxy

Our old friend. HAProxy is one of the fastest (if not _the_ fastest), most customizable load balancing proxy servers out there. It always showed excellent results in our classic deployments, barely moving the needle on resource consumption, even under full load, so I wanted to try it out [reincarnated](https://github.com/helm/charts/tree/master/incubator/haproxy-ingress) as a Kubernetes ingress controller.

All that needed to be done was to switch the ingress class from Traefik to HAProxy in our ingress resource and set the connection limit ([docs](https://github.com/jcmoraisjr/haproxy-ingress#annotations)):

{{< highlight diff >}}
... 
metadata:
  annotations:
-   kubernetes.io/ingress.class: "traefik"
+   kubernetes.io/ingress.class: "haproxy"
+   ingress.kubernetes.io/maxconn-server: "4"
...
{{< /highlight >}}

Note that Traefik gives you the ability to set the maximum connections _per backend_, whereas HAProxy allows you to set the maximum connections _per server_ -- an important differentiation of which we'll see the effect later.

How does HAProxy compare to Traefik?

| LB Type | Response Time (ms), mean | Requests / sec, mean |
|---------|--------------------------|----------------------|
| Traefik | 477                      | 50.3                 |
| HAProxy | 342                      | 70.1                 |

HAProxy is serving requests almost 30% faster than Traefik here, and ~50% faster than IP tables-based load balancing. Nice.

Looking at `top` we see full resource utilization: 

    %Cpu(s): 99.4 us,  0.4 sy,  0.0 ni,  0.1 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st

Taking a look at `kubectl top nodes`:

    NAME                             CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
    gke-indexing-bd8adade-5fh5       3994m        101%   3650Mi          29%
    gke-indexing-bd8adade-81m6       3991m        101%   3651Mi          29%
    gke-indexing-bd8adade-cd3h       3995m        101%   3565Mi          28%
    gke-indexing-bd8adade-g0lj       3994m        101%   3612Mi          29%
    gke-indexing-bd8adade-nwkp       3992m        101%   3611Mi          29%
    gke-indexing-bd8adade-zbdw       3996m        101%   3502Mi          28%

That is _efficient_.

How much difference does that `maxconn-server` annotation really make?
Well, without it, we get numbers almost identical to Traefik:

| LB Type                       | Response Time (ms), mean | Requests / sec, mean |
|-------------------------------|--------------------------|----------------------|
| HAProxy (no `server-maxconn`) | 480                      | 50.0                 |

Without proper connection limits, the load balancer is blindly doing round-robin without taking in to account how many connections it has already opened to the backend. This causes the request queue to fill up on one server while another server might actually be able to process that request, leading to inefficiency.

This can be more clearly demonstrated by observing `kubectl top nodes` with connection limiting disabled:

    NAME                             CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
    gke-indexing-bd8adade-01dm       3224m        82%    3411Mi          27%
    gke-indexing-bd8adade-4l1d       2799m        71%    2895Mi          23%
    gke-indexing-bd8adade-93l1       3746m        95%    3471Mi          27%
    gke-indexing-bd8adade-b52p       3092m        78%    3462Mi          27%
    gke-indexing-bd8adade-g0lj       3986m        101%   4729Mi          38%
    gke-indexing-bd8adade-rf9c       3464m        88%    3412Mi          27%

Quite a difference from before.

From the viewpoint of HAProxy:

{{< figure src=hap-nolimit.png caption="HAProxy: `server-maxconn` unset" >}}

Why does one server get 10 concurrent sessions while others get 2 or 3?

Compare with:

{{< figure src=hap-maxconn.png caption="HAProxy: `server-maxconn=4`" >}}

Much, much better.

---

I really like Traefik, and I think that v2.0 looks especially promising, but I didn't have a chance to check it out for this post. I did play a little with HAProxy 2.0 though, and was able to achieve similar results. 

There's also Google's recently GA'd [container-native load balancing](https://cloud.google.com/blog/products/containers-kubernetes/introducing-container-native-load-balancing-on-google-kubernetes-engine), which I have yet to play around with. As a general rule we try to keep our infrastructure cloud-agnostic to avoid vendor lock, but I may update this post if / when I get around to trying it out.

Unless Traefik 2.0 has HAProxy's ability to limit connections per server, I don't think we'll be able to consider it a viable contender to dethrone HAProxy, the king of light-speed load balancing.

Maybe we'll see such a feature added in the future.

Here's to hoping :)
