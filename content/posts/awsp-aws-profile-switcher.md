---
author: "oofnik"
title: "awsp: AWS profile switcher"
summary: |
  Simple script to make switching between AWS profiles easier.
tags: 
  - "aws"
  - "bash"
date: 2020-07-03
draft: false
---

I find myself constantly switching between AWS accounts at work.

Since we use SSO, this is a fairly tedious process without some scripted help.

I've been working on `awsp`, an AWS profile switcher. I've only tested it on bash 5.0 on Mac OS, but it should work on `zsh` / Linux too. `awsp` will modify your prompt variable to clearly indicate the active profile.

Tab completion for profiles is available for `fzf` and plain bash.

{{< github repo="oofnikj/oneliners" ref="master" file="aws/awsp.bash" lang="sh" options="linenos=inline" >}}