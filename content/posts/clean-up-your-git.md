---
author: "oofnik"
title: "clean up your git"
summary: |
  Have you ever found yourself frantically trying to un-commit some enormous binary file you've accidentally checked in to version control? Or perhaps you've made the mistake of committing your AWS root credentials?
tags: 
  - "bfg"
  - "git"
date: 2019-10-27
draft: false
---

Have you ever found yourself frantically trying to un-commit some enormous binary file you've accidentally checked in to version control? Or perhaps you've made the mistake of committing your AWS root credentials?

Enter the [BFG](https://rtyley.github.io/bfg-repo-cleaner/).

* * *

Git tries really, _really_ hard to track every single change you make to your repository. If you add a new file and commit it, then you delete the file and commit the deletion, that file will forever be stored in the commit history -- unless you do something about it.

There _are_ ways to rewrite that history. There's `git rebase`, which you can use to drop commits, making it like they never happened.

But what if, say, you want to eliminate any mention of an entire subdirectory from your repository? You could wrestle with `git filter-branch`.

In our case, we had to filter out a 700MB binary file that was committed _three years ago_. This means that every time a developer (or a CI server) cloned the repository, it had to download this file, forever archived somewhere in the inner workings of Git pack files. There are ways to speed up the clone, like using [shallow clone](https://git-scm.com/docs/git-clone#Documentation/git-clone.txt---depthltdepthgt) or [reference](https://git-scm.com/docs/git-clone#Documentation/git-clone.txt---reference-if-ableltrepositorygt) repositories, but I won't get in to that here.

Using `git filter-branch` to get rid of that commit, (which requires recalculating and repacking all 100,000 subsequent commits) would have taken _days_, even on a relatively powerful 8-core machine.

TL;DR: BFG can do most of what `git filter-branch` can, but [way faster](https://www.youtube.com/watch?v=Ir4IHzPhJuI). It's also way easier to use.

## Scrub

The basic workflow goes like this:

- do a full clone of your repository using the `--mirror` flag.  
    This means that the clone will be bare, i.e., only the stuff that normally resides in `.git` will be visible - the work tree itself will not show up.
- Run BFG with the options of your choice, depending on whether you're trying to delete binary blobs, secrets, or what have you.  
    We opted for `--strip-biggest-blobs 50`, which deletes the 50 biggest files in the repository's history, but only those that have been explicitly deleted already.
- Expire unreachable objects and run garbage collection on the repository, triggering a repack of all data:

```
$ git reflog expire --expire=now --all && git gc --prune=now --aggressive
```

This was all fairly straightforward in our case, except for one snag: The BFG part of the process took only 3 or 4 minutes. But during the repack stage, after bringing my quad core, 16 GB laptop to its knees for 30 minutes, Git was killed by OOM.

`git gc` uses `git-pack-objects` under the hood. As it turns out, this process can consume an obnoxiously huge amount of memory if your repository is big enough.

From the `git-config` man page:

> `pack.windowMemory`
> 
> `The maximum size of memory that is consumed by each thread in git-pack-objects(1) for pack window memory when no limit is given on the command line. The value can be suffixed with "k", "m", or "g". When left unconfigured (or set explicitly to 0), **there will be no limit**.`

I had to limit the window memory per thread to something reasonable to allow the process to finish:

```sh
$ git config pack.windowMemory 1g
```

Now we can re-run `git gc` as above, hopefully without running out of memory. Sit back and relax while your CPU fan prepares for take-off.

* * *

## Beam me up

Look at how much junk we got rid of:

```sh
$ cd ../repo-before && du -h -d0 .git
1.7G	.git
$ cd ../repo-after && du -h -d0 .git
652M	.git
```

Time to push your shiny new repository up to remote.

I suggest creating a new repository instead of overwriting the original with `--force`, but it's your call.

Just make sure to push everything, including your tags, since this is the only time you'll be able to do so. You can either replace your existing remote as I did to avoid confusion, or (if you're brave) create a new remote with a different name.

```sh
$ cd repo-after
$ git remote remove origin
$ git remote add origin <your_remote_url>
$ git push --set-upstream origin --all
$ git push --set-upstream origin --tags
```

### A note of warning

Because of how Git works, this process will regenerate a new commit hash for every commit that was modified, _as well as for every subsequent commit thereafter_. To make tracking things a little bit easier, the BFG will amend all of your commit messages, appending the former commit ID to them:

    commit 0012d4ea4e76a41228057b3c8da212be6ccd96bd
    Author: ...
    Date:   Wed Sep 25 16:13:21 2019 -0700
        Place all the commands in proper file names
        Former-commit-id: 29da234fbcf10dcee7272a57b2e77a74adca115e

All in all, the [ambiguously](https://en.wikipedia.org/wiki/BFG_(weapon)) [named](https://en.wikipedia.org/wiki/The_BFG) BFG is an excellent tool for shaping up Git repositories of any size.
