---
author: "oofnik"
title: "better remote desktop"
summary: |
  I was looking for something that I could use to log in to my desktop over a not so good WAN link and ended up forking Chromium.
tags:
  - "linux"
  - "rdp"
  - "ubuntu"
  - "vnc"
date:  "2020-02-08"
draft: false
---

There are a lot of names in the remote desktop world, both open source and proprietary. Most (all?) of the open source ones run on Linux. Some of the proprietary ones do too.

Two main protocols dominate the market: [RFB](https://en.wikipedia.org/wiki/RFB_protocol) (remote framebuffer) and [RDP](https://en.wikipedia.org/wiki/Remote_Desktop_Protocol) (remote desktop protocol). The classic RFB protocol is implemented in a lot of remote desktop software, mostly as some flavor of VNC. It's even built in to some operating systems and desktop environments, like Apple's [screen sharing](https://support.apple.com/en-il/guide/mac-help/mh11848/10.15/mac/10.15) for Mac OS and its [equivalent](https://help.gnome.org/users/gnome-help/stable/sharing-desktop.html.en) in GNOME. There's also the cross-platform [x11vnc](https://github.com/LibVNC/x11vnc) project.

VNC / RFB is great for running over a LAN but not so good for a high-latency WAN connection. RDP was built to one-up VNC by being smart about choosing what data to send, making it more efficient. Thankfully, RDP - originally published by Microsoft - has since been reverse-engineered and open-sourced.

I had been using an open-source RDP package called [xrdp](https://github.com/neutrinolabs/xrdp) to remote in to my Linux desktop for a while, but a couple of nagging issues led me to search for something that better suited my needs.

Firstly, since xrdp is not only a remote desktop server but also a session manager, by design it launches a virtual session separate from the console session, meaning you can't just leave all your windows open and have them be available remotely. Great if you're running a remote session manager, not so much if you just want to share your screen.

Secondly, because xrdp doesn't yet support the newer H.264 encoding mode (though it's [in the works](https://github.com/neutrinolabs/xrdp/issues/1422)), performance over limited bandwidth connections can be pretty mediocre compared to Windows-native RDP.

I filed a [bug report](https://github.com/neutrinolabs/xrdp/issues/1483) with a suggestion on how to improve things by tweaking the default TCP send buffer size, but I was still underwhelmed.

Another open source RDP implementation by the [FreeRDP project](https://github.com/FreeRDP/FreeRDP) provides a server that hooks in to your X window session allowing for true screen sharing. It also supports H.264 video encoding, solving both problems. But documentation on how to actually use `freerdp-shadow-cli` is frustratingly sparse, and I couldn't get clipboard or sound redirection to work. Unsatisfied, I kept looking.

* * *

## Chrome Remote Desktop

Google Chrome ships with a lot of extra bells and whistles, among which is a remote desktop subsystem.

Why does a web browser ship with a remote desktop subsystem, Google?

I don't know. But it works well. And it does almost what I want it to. _Almost._

There's also the benefit of not having to worry about opening ports on your router and exposing a VNC or RDP server directly to the internet (a [Really Bad Idea](https://blog.binaryedge.io/2019/05/15/rdp-exposed-on-the-internet/)). Chrome Remote Desktop uses [WebRTC](https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API) to initiate an encrypted peer-to-peer connection.

### Getting it to work on Ubuntu

As packaged, CRD won't work without some tweaking on Ubuntu 18.04. So let's dig in.

First, you'll of course need to install CRD. Visit [https://remotedesktop.google.com/access](https://remotedesktop.google.com/access) and follow the steps to get it installed on your system.

Next, we need to make a change to the PolKit configuration so our remote virtual desktop doesn't crash immediately upon startup. You can read more about this issue [here](https://c-nergy.be/blog/?p=12043), which fixes the same issue for xrdp.

Create a file called `45-allow-colord.pkla` in `/etc/polkit-1/localauthority/50-local.d/` with the following contents:

```ini
[Allow Colord all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
```

Next, generate the session file which CRD will execute to launch the desktop. We need to set some environment variables, and then launch the desktop shell:

```sh
$ cat <<EOF > ~/.chrome-remote-desktop-session
export \$(dbus-launch)
export GNOME_SHELL_SESSION_MODE=$GNOME_SHELL_SESSION_MODE 
export XDG_CURRENT_DESKTOP=$XDG_CURRENT_DESKTOP
export XDG_DATA_DIRS=$XDG_DATA_DIRS
export XDG_CONFIG_DIRS=$XDG_CONFIG_DIRS
exec $(which gnome-session) --session=ubuntu
EOF
```

Side note: The above snippet is called a [here document](https://www.tldp.org/LDP/abs/html/here-docs.html). If you're not familiar with them, it's a useful way of generating config files dynamically -- basically a template engine built right in to the shell.

Finally, restart the `chrome-remote-desktop` service:

```sh
$ sudo systemctl restart chrome-remote-desktop.service
```

And you should be good to go.

### Mirror mode

Unlike on other platforms, Chrome Remote Desktop for Linux launches a virtual desktop session separate from your main console session (just like xrdp), which can be remotely accessed. I was surprised to find, however, that there's no easy way to switch Chrome Remote Desktop to "mirror" a.k.a. shadowing a.k.a, shared mode, where the console session _is_ the remote session.

So after some sleuthing, I [hacked](https://github.com/oofnikj/chrome-remote-desktop) my own solution.

In my modified Chrome Remote Desktop, there's an additional command-line argument, `--mirror`. When set, CRD will connect to your currently active X display (almost definitely `:0`) instead of launching a separate virtual session.

You'll also find a wrapper script in the linked repository which handles things like audio redirection and sending a desktop notification upon connect and disconnect, and a `systemd` service intended to be installed in user mode to wrap it all up.

Installation instructions can be found in the [readme](https://github.com/oofnikj/chrome-remote-desktop).
