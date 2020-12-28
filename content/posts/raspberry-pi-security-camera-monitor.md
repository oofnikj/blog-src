---
title: "raspberry pi security camera monitor"
summary: |
  A remote Raspberry Pi-powered display for a video surveillance system.
date: "2019-12-28"
tags: 
  - "dvr"
  - "raspberrypi"
---

I took some time off between jobs. Among the things I did with my down time, I set up a secondary monitor for an IP camera system. Here is how it works.

My dad had a couple of security cameras installed. They all feed in to a DVR that sits next to his computer. Besides recording, the thing muxes the camera feeds into a single picture-in-picture stream which is known in security-camera-speak as "channel zero".

There's a monitor that sits on top of the DVR to display a live view, play back recorded video, and configure the system though an spectacularly non-intuitive interface. An additional monitor was installed in the kitchen that's hard-wired over a special run of coax directly to the DVR.

My dad is down in the basement a lot, and he wanted a monitor set up there too. But running another coax wasn't possible for several reasons.

This got me thinking.

In addition to muxing and recording the camera streams, the thing is wired to the home network.

After some googling and poking around, I figured out that all the video streams are [accessible](https://www.use-ip.co.uk/forum/threads/hikvision-rtsp-stream-urls.890/) via RTSP over the network.

All I had to do was set up something to connect to the wifi, stream the video, and display it on a monitor. Sounds like the perfect job for a Raspberry Pi Zero W.

* * *

## Stream

I'm not going to go in to the details of setting up a Raspberry Pi to be accessible over the network via SSH, because there are already a [bazillion](https://magpi.raspberrypi.org/articles/ssh-remote-control-raspberry-pi) [guides](https://itsfoss.com/ssh-into-raspberry/) [out](https://www.raspberrypi.org/documentation/remote-access/ssh/) [there](https://learn.adafruit.com/adafruits-raspberry-pi-lesson-6-using-ssh/enabling-ssh) on how to that. But that's the first step.

Now we need to set up some kind of video playback. My usual go-to would be [VLC](https://www.videolan.org/vlc/index.html), but I found that in this case, the Zero W didn't have enough oomph for smooth playback.

Next I tried `omxplayer` which apparently comes pre-built with hardware acceleration, and that seemed to work much better.

Here you need to know the IP address of your DVR, which you can find by wading through the garbage UI and eventually stumbling upon it by accident. Alternatively, you could look up the DHCP leases in your router's config page and see what address it assigned to the DVR, assuming you're using DHCP.

You also need to know the port on which the DVR is listening for incoming RTSP connections. The standard port for RTSP is 554, but my unit was configured to listen on 10554. YMMV.

The final command line to get `omxplayer` to play our video stream looks like this:

```sh
$ omxplayer --loop --live --timeout 120 --avdict rtsp_transport:tcp \
  rtsp://<user>:<pass>@<ip>:<port>/Streaming/channels/001
```

Replace the bits in angle brackets and you should see your stream. You can read more about the command-line options available to `omxplayer` [here](https://www.raspberrypi.org/documentation/raspbian/applications/omxplayer.md).

Note: You can play different camera streams by changing the number at the end. The first digit indicates which channel (we're playing the muxed channel, channel-zero). The second and third digits indicates whether you're playing the main, high-definition stream (`01`) or the standard-definition one (`02`) suitable for low-bandwidth connections.

## Resilience

I want the stream to be completely automatic and resilient, such that it should be able to accommodate several failure conditions and self-recover. Simply running `omxplayer` as above manually on startup wasn't going to cut it.

Instead, I configured `omxplayer` to launch as a [systemd](https://en.wikipedia.org/wiki/Systemd) service at startup that would respawn if anything went wrong.

Fire up an editor to create a `systemd` service:

```sh
$ sudo vi /etc/systemd/system/dvr.service
```

And here's what should go inside:

```ini
[Unit]
Description=Security camera
Requires=network.target
[Service]
Type=simple
ExecStart=/usr/bin/omxplayer --loop --live --timeout 120 --avdict rtsp_transport:tcp "rtsp://<user>:<pass>@<ip>:<port>/Streaming/channels/001"
User=pi
StandardOutput=null
Restart=always
RestartSec=10
[Install]
WantedBy=graphical.target
```

You can read more about what all these parameters do over [here](https://www.freedesktop.org/software/systemd/man/systemd.service.html). But basically, we're telling `systemd` to wait until the network is available before launching our service, and restarting it if it exits with a delay of 10 seconds between restart attempts.

Save the service file and exit. Now we need to tell `systemd` to re-read our service definitions, enable it, and start it:

```sh
$ sudo systemctl daemon-reload
$ sudo systemctl enable dvr.service
Created symlink /etc/systemd/system/graphical.target.wants/dvr.service → /etc/systemd/system/dvr.service.
$ sudo systemctl start dvr.service
```

And with any luck, you should see your video stream pop up.

You can also reboot your pi now to confirm that the video comes up on boot.

* * *

## Resilience (cont.)

I had an additional problem (apparently I'm not the [only](https://github.com/raspberrypi/linux/issues/1342) [one](https://www.raspberrypi.org/forums/viewtopic.php?t=233847) either) where occasionally the onboard wifi on the Pi Zero W would hard crash at random intervals, and the only way to get it back online was to either power cycle the pi, or power cycle the router, neither of which were particularly palatable solutions.

I did find, however, that whenever this hard crash happened, a bunch of error messages appeared in the kernel log, `/var/log/kern.log`:

```log
Dec 22 03:55:23 raspberrypi kernel: [151994.344119] brcmfmac: brcmf_cfg80211_scan: scan error (-110)
Dec 22 03:56:23 raspberrypi kernel: [152054.344514] brcmfmac: brcmf_run_escan: error (-110)
Dec 22 03:56:23 raspberrypi kernel: [152054.344542] brcmfmac: brcmf_cfg80211_scan: scan error (-110)
Dec 22 03:57:23 raspberrypi kernel: [152114.344934] brcmfmac: brcmf_run_escan: error (-110)
Dec 22 03:57:23 raspberrypi kernel: [152114.344962] brcmfmac: brcmf_cfg80211_scan: scan error (-110)
Dec 22 03:58:23 raspberrypi kernel: [152174.345345] brcmfmac: brcmf_run_escan: error (-110)
Dec 22 03:58:23 raspberrypi kernel: [152174.345372] brcmfmac: brcmf_cfg80211_scan: scan error (-110)
Dec 22 03:59:23 raspberrypi kernel: [152234.345824] brcmfmac: brcmf_run_escan: error (-110)
```

So I wrote a script to check for network connectivity, and unload / reload the kernel module if it goes away:

{{< gist oofnikj 9b653e58d1f887fc166b7eb700e327b6 >}}

Put this script in `/usr/local/bin` and run it every five or so minutes via `crontab`:

```sh
$ curl -sL https://gist.github.com/oofnikj/9b653e58d1f887fc166b7eb700e327b6/raw/f26e87d9299e74eb5844a6e5d0fb335638376fba/wififix.sh | \
  sudo tee /usr/local/bin/wififix.sh
$ sudo chmod +x /usr/local/bin/wififix.sh
$ sudo bash -c "cat <(crontab -l) <(echo '*/5 * * * * /usr/local/bin/wififix.sh') | crontab -"
```

It takes the pi about 30 seconds to regain connectivity when this happens, so the video freezes for that amount of time, but it always* comes back.

*until the next failure mode reveals itself.
