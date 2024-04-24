# Ziguencer

A MIDI sequencer written in Zig

## Motivation

### Hackable alternative to hardware sequencers

Ziguencer is a lightweight stand-alone pattern-based MIDI sequencer. 
It's meant to run on small devices such as Raspberry PI (as old as the first model B), to function as a cheap, light-weight alternative to more expensive hardware MIDI sequencers,
such as the [Squarp Hapax](https://squarp.net/hapax/) or the [Toraiz Squid](https://www.pioneerdj.com/en/landing/toraiz/toraiz-squid/).

Since Ziguencer written in a relatively high-level language, and is open source, 
it is much more hackable than proprietary hardware sequencers. New features and bug fixes aren't dependent on firmware updates from the vendor.

### Endavour in Zig

As a programmer spoiled with the luxury of garbage collectors, Ziguencer is also a great way for me to understand the low-level details of programming, 
with fewer footguns than C, and a couple of awesome features as a bonus. For instance Ziguencer already leverages:
- easy integration with cross-platform C libraries ([PortMidi](https://github.com/PortMidi/portmidi))
- compilation to another target platform (From Mac to ARM linux on Raspberry Pi)

## Features

- Pattern-based sequencing (Ableton Live-like)
- [Launchpad](https://novationmusic.com/launch) UI for viewing and editing

## Future plans
- Support for LED display on Raspberry PI
- Integration with multiple MIDI devices

## Usage

### Prerequisites
The libraries `portmidi` and `notcurses` need to be installed and available.

Usually it's a matter of running `brew install portmidi notcurses` or similar on your platform.

### Starting

First build the binary, specifying the target platform, eg Mac:

```bash
zig build -Dmac
```

The run it:
```bash
./zig-out/bin/ziguencer 
```
The program should you a list of available midi devices and exit. 

You can then start the program specifying devices:

```bash
./zig-out/bin/ziguencer --out [device name/number] (--in [device name/number]) (--launchpad auto)
```

Example:
```
./zig-out/bin/ziguencer --out fluidsynth --launchpad auto
```

The `--out` parameter is mandatory. 

### Using

TODO 
