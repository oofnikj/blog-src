---
author: "oofnik"
title: "kernel patching with dkms"
summary: |
  How do you maintain a patched version of an in-tree Linux kernel module?
tags: 
  - "dkms"
  - "linux"
  - "openwrt"
  - "wifi"
date: "2020-09-12"
draft: false
---

## The Problem

For my [Dockerized router project]({{< ref "contain-your-router" >}}), I had to find a way to broadcast a 5 GHz Wi-Fi signal from my desktop hardware -- a function that's almost exclusively the domain of embedded wireless routers and access points.

It turns out that the Wi-Fi module that came with my Intel NUC is notoriously non-cooperative. The `iwlwifi` kernel driver for Intel Wi-Fi modules simply refuses to do such a thing.

After some Googling, I learned that Qualcomm / Atheros Wi-Fi chipsets are more amenable to operating in AP mode at 5 GHz. So I had to go find a suitable Wi-Fi module that would work.

A quick trip to the local laptop repair shop later, I had a Lenovo-branded M.2 Wi-Fi module with an Atheros chipset ready to swap with the stock Intel hardware.

For anyone wondering, here's the exact hardware spec:

```sh
$ lspci -kvnn
02:00.0 Network controller [0280]: Qualcomm Atheros QCA6174 802.11ac Wireless Network Adapter [168c:003e] (rev 20)
	Subsystem: Lenovo QCA6174 802.11ac Wireless Network Adapter [17aa:3044]
	Flags: bus master, fast devsel, latency 0, IRQ 131
	Memory at 91000000 (64-bit, non-prefetchable) [size=2M]
	Capabilities: <access denied>
	Kernel driver in use: ath10k_pci
	Kernel modules: ath10k_pci
```

Wireless chipsets supported by the `ath` family of kernel modules are able to broadcast on 5 GHz, but there's a catch: the stock driver code compiled for and delivered with most Linux distributions almost certainly will not allow you to do it.

By default, the kernel driver looks at two things: the wireless regulatory domain etched in to the EEPROM of the hardware, and the software [wireless regulatory database](https://wireless.wiki.kernel.org/en/developers/regulatory/wireless-regdb). The combined restrictions from both are what determine the channels on which a radio can initiate a broadcast, a function required to run in access point mode. A more detailed overview can be found [here](https://wireless.wiki.kernel.org/en/users/drivers/ath#regulatory).

The OpenWrt project, an embedded Linux distribution designed to run on wireless routers and networking gear, maintains a set of patches[[4]](#references) for the `ath` kernel module which allow for a custom regulatory domain to be set by the user. Which leads us to...

## The Solution

Running an OpenWrt filesystem on a stock Linux kernel is possible, but we need a way to incorporate those tweaks if we want to run our wireless hardware in 5GHz AP mode. That's what [ath\_user\_regd](https://github.com/oofnikj/ath-user-regd) is for.

If you've ever installed VirtualBox or an external kernel driver for some hardware, you probably came across [DKMS](https://github.com/dell/dkms), the dynamic kernel module support package. DKMS is a collection of clever shell scripts available for most Linux distros that can automatically recompile the source code for a kernel module whenever a new kernel is installed. VirtualBox uses DKMS hooks to do exactly that to keep your virtual machines running after a kernel upgrade. I use it for `ath_user_regd` to maintain a patched version of the `ath` kernel module with the OpenWrt patches applied.

Instructions for use are in the [repo link](https://github.com/oofnikj/ath-user-regd).

But please, before using it, **read the disclaimer**. I'm not responsible if you fry your Wi-Fi hardware, break laws, or do other not-smart things.

Credit to Renaud Cerrato's [DIY router article](https://medium.com/@renaudcerrato/how-to-build-your-own-wireless-router-from-scratch-c06fa7199d95) for the original idea.

## References

1. [https://badgateway.qc.to/contain-your-router](https://badgateway.qc.to/contain-your-router)
2. [https://wireless.wiki.kernel.org/en/developers/regulatory/wireless-regdb](https://wireless.wiki.kernel.org/en/developers/regulatory/wireless-regdb)
3. [https://wireless.wiki.kernel.org/en/users/drivers/ath#regulatory](https://wireless.wiki.kernel.org/en/users/drivers/ath#regulatory)
4. [https://github.com/openwrt/openwrt/blob/master/package/kernel/mac80211/patches/ath/402-ath\_regd\_optional.patch](https://github.com/openwrt/openwrt/blob/master/package/kernel/mac80211/patches/ath/402-ath_regd_optional.patch) and [https://github.com/openwrt/openwrt/blob/master/package/kernel/mac80211/patches/ath/406-ath\_relax\_default\_regd.patch](https://github.com/openwrt/openwrt/blob/master/package/kernel/mac80211/patches/ath/406-ath_relax_default_regd.patch)
5. [https://github.com/dell/dkms](https://github.com/dell/dkms)
6. [https://github.com/oofnikj/ath-user-regd](https://github.com/oofnikj/ath-user-regd)
7. [https://medium.com/@renaudcerrato/how-to-build-your-own-wireless-router-from-scratch-part-3-d54eecce157f](https://medium.com/@renaudcerrato/how-to-build-your-own-wireless-router-from-scratch-part-3-d54eecce157f)
