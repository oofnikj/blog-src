---
author: "oofnik"
title: "how to make a blog"
summary: |
  I've been meaning to do this for quite some time.
tags:
  - apache
  - GCP
  - meta
  - SSL
  - wordpress
date: 2019-09-27T18:20:32+00:00
draft: false
---

I'm going to start with a meta-post. I've been meaning to do this for quite some time.

Since this is a blog about devops, I'm going to share some useful tidbits on how to set up a blog on GCE (Google Compute Engine) for cheap.

---

Google Cloud Platform has a marketplace of pre-baked VM images that you can launch with the click of a button. I found one called "WordPress". When you click "Launch on Compute Engine", it spins up an instance of a size and region of your choosing, and provides you with temporary credentials with which you can log in to your installation.

Nifty.

Next, I needed a DNS record to point to my instance's public IP address.

My go-to domain provider is [Duck DNS](https://www.duckdns.org). But badgateway.duckdns.org was already taken. Next up: [FreeDNS](https://freedns.afraid.org/). I browsed through the list of available domains and found something nice and short. Register, wait a couple minutes, and voila! Free domain name.

Step 3: Encryption. Nobody likes to see this warning:

{{< figure src=http.png >}}

So let's get some SSL with [Certbot](https://certbot.eff.org/). Since my VM is running Debian, we have the ultimate Swiss-army knife of package management available to us - apt.

EFF gives us a nice little howto for most common webserver installations. Indeed, Debian Buster + Apache was [included](https://certbot.eff.org/lets-encrypt/debianbuster-apache).

Install Certbot and the Apache plugin:

{{< highlight sh >}}
$ sudo apt-get install certbot python-certbot-apache
{{< /highlight >}}

And now we can install the cert:

{{< highlight sh >}}
$ sudo certbot --apache
{{< /highlight >}}

You'll have to enter in some details like your domain and e-mail for the certificate to be properly generated. If all goes well, you'll have a certificate installed at `/etc/letsencrypt/live/<YOUR_DOMAIN>`.

Okay, so now when someone visits **http://** badgateway.qc.to, how are they redirected to **https://** badgateway.qc.to?

We could get our hands dirty in Apache config files, _or_ take advantage of someone who [already did the work for us](https://really-simple-ssl.com). Install the plugin, enable it, and you should be flying high.

Oh! I almost forgot. Permalink redirects didn't work out-of-the-box for me because of a restrictive Apache setting.

[The fix](https://www.techiediaries.com/wordpress-permalinks-not-working-404-error/): Open up `/etc/apache2/apache2.conf` and tweak this part:

{{< highlight diff >}}
<Directory /var/www/>
     Options Indexes FollowSymLinks
-    AllowOverride None
+    AllowOverride All 
     Require all granted
</Directory>
{{< /highlight >}}

Now just restart Apache with

{{< highlight sh >}}
$ sudo systemctl restart apache2
{{< /highlight >}}

And that should do it.

