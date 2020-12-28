---
author: "oofnik"
title: "contain your router"
summary: |
  I hate home router hardware. I really do. So I set out on building a replacement -- without spending any money.
tags: 
  - "docker"
  - "hostapd"
  - "networking"
  - "openwrt"
  - "wifi"
date: "2020-02-20"
draft: false
---

I hate home router hardware. I really do. So I set out on building a replacement -- without spending any money.

* * *

## Why?

What the marketing world refers to as a 'router' actually combines several functions into a single hardware device: gateway, firewall, switch, wireless access point, DNS, DHCP, and sometimes DSL / cable modem.

Save for the modem part, we can do all of that on any Linux box. In fact, almost all home router devices (including the one you got from your ISP) are penguin powered.

I hate consumer-grade routers because they are built with cheap, unreliable, developer-unfriendly hardware, running vulnerable, outdated, crippled software.

If you're lucky, your router hardware is supported by one of the open router firmware projects like [OpenWRT](https://openwrt.org/) or [FreshTomato](https://exotic.se/freshtomato/). But even then, hardware limitations might prevent you from installing the packages you'd like to run, like a VPN or torrent client. Or there might be unfixable bugs because the hardware vendor won't release up-to-date driver source code.

So here's an idea: why not run a router OS on normal PC hardware?

## Bare metal vs. VM vs. container

First, we need to decide how we're going to deploy this virtual router.

If we deploy to bare metal, we need a spare computer lying around with the right hardware.

But let's say you don't have spare computer lying around, and you want to utilize the hardware you've got for more than just routing? Virtualization is a great solution for this.

I actually started this project with virtualization using VirtualBox, until I learned that 1) PCI passthrough support was [silently](https://www.virtualbox.org/ticket/14584#comment:2) [removed](https://forums.virtualbox.org/viewtopic.php?f=7&t=96625#p468864) (thanks, Oracle!) relatively recently, and 2) USB Wi-Fi adapters have slim-to-none 802.11ac support in AP mode under Linux. So I switched to KVM / Libvirt, which can do PCI passthrough just fine.

But.

Then I spent a couple of days messing with [VFIO and IOMMU groups](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF), and I learned that with my particular hardware, it's not possible to pass just the Wi-Fi card through to the VM, but the Ethernet adapter must be passed too.

My Ethernet chipset did not appreciate this, and would require a cold reboot to get going again, even back on the host. So much for that plan.

I did a little reading and found out that Docker [supports](https://docs.docker.com/network/macvlan/) a network driver called `macvlan`, which allows a container to be directly connected to a host's network interface by creating a virtual sub-interface with a unique MAC address - just like layer 2 VM bridging.

If we can get our router platform running in Docker, this might be the golden ticket.

## Choosing a platform

While we can do the routing, switching, access point-ing and so on directly with Linux CLI tools like `ip`, `iptables`, `hostapd` and so on, it's awfully convenient to have a unified UI to configure your network settings.

In addition to the open-source projects targeting embedded devices listed above, there are quite a few purpose-built Linux distributions designed to run on common x86 hardware like IPFire, Openwall, and ClearOS. There's even a Wikipedia page [dedicated to them](https://en.wikipedia.org/wiki/List_of_router_and_firewall_distributions).

Glaring omissions pfSense and OPNsense are excluded because they are based on FreeBSD, not Linux. I've used both pfSense and OPNsense in professional environments and can vouch for their performance and stability, but there are two big problems that take them out of the running for this project:

1. They are built upon FreeBSD, not Linux, which means they must be run either in a VM or on bare metal. We're doing containers here.  
    
2. [pfSense can't do 802.11ac in AP mode](https://docs.netgate.com/pfsense/en/latest/book/wireless/pfsense-as-an-access-point.html#should-an-external-ap-or-pfsense-be-used-for-an-access-point). I'm not sure if this is a limitation of FreeBSD or just pfSense, but either way, for me it's a deal-breaker.

I'm going to fast-forward here and just tell you why I picked OpenWRT: I've installed it before, I like the built-in package management system `opkg`, it has a great CLI configuration management tool called `uci`, it's tiny (less than 4 megabytes!), and the web interface is actually quite polished.

Oh, and there are already pre-built images available on [Docker Hub](https://hub.docker.com/r/openwrtorg/rootfs/tags).

## Teleport the Wi-Fi

We need OpenWRT to be able to directly control our Wi-Fi interface from inside a container. But how?

Containers are isolated from the host in several ways. They have their own PID namespace, their own user namespace, and their own network namespace. But since containers are all running atop the host kernel, we can expose various resources from the host to the container, like network interfaces, by moving them from the primary namespace to that of the container.

Docker provides a `--network=host` option, where your container runs in the _same_ network namespace as the rest of the system's processes. But if you only want a single interface to be controlled directly by the container, you need to do some command-line voodoo.

Here's a quick demonstration of how this works.

Note -- this only works on Linux hosts, and it will knock out your internet connection if you're connected over the interface you're moving. You've been warned.

Also, depending on your Wi-Fi drivers, this might not work at all. Some drivers support setting the network namespace while others will return an error.

If your Wi-Fi works on your distro out of the box (i.e., you didn't need to compile your own drivers), chances are the drivers are part of the official mainline kernel, and you should be fine.

- Run a detached container:

    ```sh
    $ docker run --rm -it -d --name netns-test alpine
    17da7018a16ce46ce87a1f14d263e3fc367ea9c1d2d0a896e812c652445042a0
    ```

- Get the container's parent PID:

    ```sh
    $ PID=$(docker inspect -f '{{.State.Pid}}' netns-test)
    ```

- Get our Wi-Fi interface name:

    ```sh
    $ ip link show
    ...
    4: wlp2s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP mode DORMANT group default qlen 1000
        link/ether xx:xx:xx:xx:xx:xx brd ff:ff:ff:ff:ff:ff
    ...
    ```

- Get the physical device associated with our interface:

    ```sh
    $ PHY=$(cat /sys/class/net/wlp2s0/phy80211/name)
    ```

- Move our device to the container namespace:

    ```sh
    $ sudo iw phy $PHY set netns $PID
    ```

- Show that the interface is now inside the container namespace:

    ```sh
    $ docker exec netns-test ip link show wlp2s0
    4: wlp2s0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN qlen 1000
        link/ether xx:xx:xx:xx:xx:xx brd ff:ff:ff:ff:ff:ff
    ```

- And not in our host namespace:

    ```sh
    $ ip link show dev wlp2s0
    Device "wlp2s0" does not exist.
    ```

- Shut it down to get our Wi-Fi back:

    ```sh
    $ docker kill netns-test
    ```

* * *

## Wrapping up

I've written a script to automate the process of setting up OpenWRT in Docker and moving the Wi-Fi interface which you can find, along with instructions, [here](https://github.com/oofnikj/docker-openwrt).

The script will generate the OpenWRT config at runtime from templates based on the configuration you provide. A sample configuration file is provided for reference. At the very least you'll need to change the values of `LAN_PARENT` and `WIFI_IFACE`.

If you're going to run this behind your existing router, keep in mind that from the container's perspective, WAN is anything upstream (i.e., your existing LAN), while LAN is the Wi-Fi access point and its clients, plus the container host, connected with a virtual Ethernet interface.

By default, LAN devices can access anything upstream, but (like any sane router configuration) firewall rules prevent devices from the WAN zone from accessing the web UI or anything in the LAN without port forwarding.

It's certainly possible to configure OpenWRT without a WAN zone and to set it up to act as a bridge between your existing wired LAN and your wireless devices.

Check out the links below for references on how to configure OpenWRT to your liking.

Also, have a look at how I [patched]({{< ref "kernel-patching-with-dkms" >}}) my kernel to broadcast 802.11ac Wi-Fi at 500 Mbps.

* * *

### References

- [https://platform9.com/blog/container-namespaces-deep-dive-container-networking/](https://platform9.com/blog/container-namespaces-deep-dive-container-networking/)
- [https://docs.docker.com/network/network-tutorial-macvlan/](https://docs.docker.com/network/network-tutorial-macvlan/)
- [https://github.com/sdelrio/rpi-hostap](https://github.com/sdelrio/rpi-hostap)
- [https://openwrt.org/docs/guide-user/network/ucicheatsheet](https://openwrt.org/docs/guide-user/network/ucicheatsheet)
- [https://openwrt.org/docs/guide-user/network/start](https://openwrt.org/docs/guide-user/network/start)
