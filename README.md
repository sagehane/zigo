<!--
SPDX-FileCopyrightText: 2023 Sage Hane <sage@sagehane.com>

SPDX-License-Identifier: CC0-1.0
-->

### What is this?

An opinionated implementation of Go/Baduk/Weiqi, named after [Zig](https://ziglang.org/)
and [Jigo](https://en.wikipedia.org/wiki/List_of_Go_terms#Jigo).

Licensed under [Creative Commons Zero v1.0 Universal](https://spdx.org/licenses/CC0-1.0).

### How to build and run:

Get a recent version of Zig (tested on `0.12.0-dev.2014+289ae45c1`) and run `zig build run`.

### Rules:

The rules are identical to the [New Zealand Rules of Go](https://www.go.org.nz/index.php/about-go/new-zealand-rules-of-go)
unless specified otherwise.

(The text in bold emphasises terminology from the rules on the site)

While an **even game** is played on a 19x19 board with a **komi** of 7, zigo
supports board dimensions up to 255x255 and a **komi** of 65,535 (2^16-1).

**Handicap games** are yet to be supported.

A **play** cannot result in a **board repetition** and there is no penalty for
attempting to make one.

The game is **finished** if and only if a player forfeits or a **pass** results
in a **board repetition**.

Once **finished**, the **territory** is counted immediately with no allowance of
removing **"dead" stones**.

Forfeiting: While the game is **unfinished**, either play may forfeit at any
time to **finish** the game at the result of their loss.
