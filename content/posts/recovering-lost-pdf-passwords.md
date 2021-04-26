---
author: "oofnik"
title: "recovering lost pdf passwords"
summary: |
  How to recover a lost PDF password using open source tools.
tags:
  - john
  - bruteforce
  - encryption
date: 2021-04-26T22:15:01+03:00
draft: false
---

Sometimes we misplace important pieces of information. We write passwords on sticky notes that get thrown out, delete old junk that turned out to not actually be junk, or assume something was committed to memory when it fact you discover those sectors got overwritten by what you ate for breakfast when you go looking for it.

It turns out that if you know even just a little bit about the nature of the information you're trying to recover, it becomes exponentially easier to to do so.

## Brute Force

There are all sorts of clever tricks and shortcuts to cracking a password that often depend on some weakness of the implementation (think of lock picking), but the most sure-fire (and dumbest) way to get your password back is to brute force your way in. While brute force might conjure up images of trying to kick down a locked door until the wood splinters, it's really more like bringing a keyring with several hundred million keys and trying every single one. It may take a long time, but you can cut the time needed down by orders of magnitude if you're smart about which keys you actually try.

We'll use two popular open-source tools, `crunch` and `john`, to accomplish our goal.

***

## Know Your Enemy

If you don't know anything about the password you're trying to recover, you're in for a potential eternity of guessing. That's why authentication mechanisms that let on something about the nature of a failed authentication attempt are such a bad idea -- they give an attacker information that can be used to potentially reduce the time needed to crack by an enormous factor because now he knows what *not* to try. Even a variation in time between attempts can be construed as information about the length or complexity of the password in question.

But let's say you're not Mr. Robot. Let's say, instead, you're just trying to open your final pay stub from your previous employer who sent it to you as an encrypted attachment, and you really don't feel like e-mailing their HR department *queue nervious laugh*. You probably know enough about your lost password to cut the guessing time down from 86 years on the [OLCF-4](https://en.wikipedia.org/wiki/Summit_(supercomputer)) to a couple of hours on your 4-core MacBook Pro. You probably know, for example, how long it is, which characters are in it, and maybe you're even pretty sure about the numbers at the end.

With that knowledge, we can use `crunch` to generate a word list of all plausible permutations of the password we're trying to guess.

In my case, I knew that I was looking for a password that was:
1. six characters in length
2. composed exclusively of capital letters (A-Z) and numbers (0-9)

## Attack

So we run `crunch` like this (consult the `man` page for how the options work):

```shell
$ crunch 6 6 ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890 -o wordlist.txt
Crunch will now generate the following amount of data: 15237476352 bytes
14531 MB
...
```

`crunch` will deterministically iterate over all possible combinations of characters according to our parameters. After a few moments, we get 15 gigabytes of newline-delimited plaintext with our password presumably buried somewhere deep within.

The next tool we're using is called [John the Ripper](https://www.openwall.com/john/). `john`, for short, is a suite of "security auditing" tools that have been around for quite a while used to ~~crack~~ audit all kinds of passwords -- encrypted Word documents, ZIP files, PDFs, *nix `/etc/passwd` hashes, you name it.

There's probably a native way to install `john` on your OS, but just to be sure we obtain the full suite, we'll download and compile it from source. I mean, we're hackers now, right?

```shell
$ git clone https://github.com/openwall/john.git
$ pushd john/src && ./configure && make -j$(nproc)
$ popd
```

We're using a PDF as our example, so we'll use the `pdf2john` Perl script which comes with the suite to extract the password hash embedded in our document.

```shell
$ john/run/pdf2john.pl document.pdf > document.hash
```

And now, the fun part.

```shell
$ john/run/john --wordlist=wordlist.txt --fork=$(nproc) document.hash
```

    Using default input encoding: UTF-8
    Loaded 1 password hash (PDF [MD5 SHA2 RC4/AES 32/64])
    Cost 1 (revision) is 3 for all loaded hashes
    Node numbers 1-8 of 8 (fork)
    Press 'q' or Ctrl-C to abort, almost any other key for status
    ...
    Use the "--show --format=PDF" options to display all of the cracked passwords reliably
    Session completed.

The `--fork=$(nproc)` bit will tell `john` to split the work up across all available CPU cores on your system.`john` will stop when it finds a match.

I was sitting on the other side of the room; I knew it was done when the fans stopped whirring at full blast.

```shell
$ ./john/run/john --show --format=PDF document.hash
doc.pdf:ABC123
```

Bada-*boom*.

***

## Sources
1. https://en.wikipedia.org/wiki/Summit_(supercomputer)
1. https://tools.kali.org/password-attacks/crunch
1. https://www.openwall.com/john/