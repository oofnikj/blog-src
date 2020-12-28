---
author: "oofnik"
title: "postgres <--> google cloud storage"
summary: |
  Don't run a database if you can get away with it.
date: "2019-10-13"
tags: 
  - "gcs"
  - "postgres"
---

We have a PostgreSQL database server that stores a bunch of product catalogs. It weighs in at around 2 TB.

The vast majority of the time, this data is just sitting there on SSD provisioned storage, waiting to be accessed by a batch indexing job.

  
This costs something on the order of $0.20 per GB per month.

That is quite a bit of money.

So I wrote a script to dump all the catalogs to Google Cloud Storage, one by one.

When we need one of them, we spin up a PostgreSQL instance and restore only the DB we need for the duration of the job, then delete the instance.

{{< gist oofnikj 4ee432033421f34b548ae2891067efcf >}}
