---
author: "oofnik"
title: "migration to hugo"
summary: |
  Recap of migrating from Wordpress to Hugo.
tags:
  - blog
  - wordpress
  - hugo
date: 2020-12-29T09:53:26+02:00
draft: false
---

In [a previous blog post]({{< ref "postgres-google-cloud-storage" >}}), I wrote that you shouldn't run a database if you don't have to. 

Well, I wasn't exactly following my own advice by hosting this blog on a cloud instance running Wordpress. The time has come to migrate to using a static page generator -- something I've wanted to do for a while but put off because I dread frontend stuff.

I'd experimented here and there with Jekyll and Hugo and GitHub Pages and all that, but I was wholly unsatisified with the migration tools I found. They all left me with some yucky half-markdown-half-HTML mess that required a bunch of manual regexing. There's not a _whole_ lot on here, but it got pretty tiring after a few hundred lines.

And then I found [wordpress-export-to-markdown](https://github.com/lonekorean/wordpress-export-to-markdown), which did an absolutely fantastic job. So, shoutout to [lonekorean](https://github.com/lonekorean) on GitHub for that gem.

I more or less followed the Hugo [getting started guide](https://gohugo.io/getting-started/quick-start/) using the Git submodule layout. After finding a [theme](https://github.com/vaga/hugo-theme-m10c), doing some [tweaking](https://mertbakir.gitlab.io/hugo/tag-cloud-in-hugo/), and organizing the content, things were more or less ready to publish.

As a finishing touch, I added a pre-commit hook to rebuild the site and commit the changes to the submodule repository whenever I add or change content.

{{< github repo="oofnikj/blog-src" ref="main" file="publish.sh" lang="sh" options="linenos=table" >}}

From the source repository:

```sh
$ cd .git/hooks && ln -s ../../publish.sh pre-commit
```

As long as `publish.sh` is executable, the commit hook will regenerate your static site and update the submodule refrence.

Finally, configure Git to push changes to submodules as needed:

```sh
$ git config push.recurseSubmodules on-demand
```

Publishing changes is just a  `git add . && git commit` away.

Bye, Wordpress.