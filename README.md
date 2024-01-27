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
- compilation to another target platform (ARM linux)

## Features

- Pattern-based sequencing (Ableton Live-like)
- Launchpad UI for viewing and editing

## Future plans
- Support for LED display on Raspberry PI
- Integration with multiple MIDI devices
