---
author: "{{ .Site.Params.author }}"
title: "{{ replace .Name "-" " " | lower }}"
summary: |
  short summary goes here
tags:
  - tag1
  - tag2
  - tag3
date: {{ .Date }}
draft: true
---
