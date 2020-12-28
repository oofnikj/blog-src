---
author: "oofnik"
title: "backing up wordpress with git"
summary: |
  So I started this blog, and it's running on a virtual server somewhere in the cloud. What happens if it disappears?
tags:
  - backup
  - git
  - revisr
  - wordpress
date: 2019-09-29T05:53:06+00:00
draft: false
---

So I started this blog, and it's running on a virtual server somewhere in the cloud. What happens if it disappears? 

---

This worried me. So I set out to find a backup solution. <br><br>After some googling, here's what I came up with.

<p style="text-align:left">I found a plugin called <a href="https://wordpress.org/plugins/revisr/">Revisr</a> which can automagically commit changes to your WordPress directory and/or database to a Git repo, and push them to a remote. After activating it, a new section gets added to your admin dashboard where you can configure the plugin's settings, like the path to your remote, authentication, etc.<br><br>So I did all of that, and lo and behold:

{{< figure src=error.png >}}

Time to roll up the sleeves and pull out the `SSH`.

Revisr initializes a `.git` directory in your WordPress root and commits everything it finds in there, unless you configure it to do otherwise. It forks a subprocess as the same user as your webserver, typically `www-data`. Since `www-data` doesn't have access to my private SSH key I use to authenticate with my remote Git repository, no dice.

So we need to create a SSH key pair for `www-data`:

{{< highlight sh >}}
$ sudo -u www-data ssh-keygen
{{< /highlight >}}

And then add the public key to our remote with write access. 

Next problem: host key checking. 

By default, SSH refuses to connect to hosts whose keys it's never seen before. If you've ever seen this prompt:

{{< highlight code >}}
The authenticity of host 'xxx.xxx.xxx.xxx' can't be established.
RSA key fingerprint is SHA256:blahblahblah.
Are you sure you want to continue connecting (yes/no)?
{{< /highlight >}}

And then you type `y <Enter>`, and then SSH kindly asks you to explicitly either type `yes` or `no`, and you go _"ughhh"_... yeah. That's host key checking.

To fix it, we need to add our remote's host key to `www-data`'s known hosts file. This can be done by doing what Revisr already tried and failed to do - pushing to remote - but since we're in an interactive shell, we can type `yes` and be on our merry way:

{{< highlight sh >}}
$ cd /var/www/html
$ sudo -u www-data git push -u origin master
{{< /highlight >}}

Note the `sudo` again - we have to make sure we're doing things as the right user, and chances are, you're not logged in to your server as `www-data` given that his login shell is `/usr/sbin/nologin` by default. **Don't change this**.

You should get a prompt about your remote server's host key. Once we've added the key and performed our first push, Revisr should have no problem pushing future changes.

Blog away, worry-free.
