<!-- What changed, and what it is for. -->

### Checks

- [ ] `luajit test_harness.lua` passes
- [ ] `python3 build.py` run, and the resulting `AchaeaHidden.xml` is committed
- [ ] Any new rule about how Achaea behaves cites a scroll or a line the game
      actually printed

<!--
The .xml is generated from the .lua and is what actually gets installed, so a
.lua edited without a rebuild ships a package that does not match its source.
CI checks this, but it is cheaper to notice here.

Version: 0.x, so minor for a change in behaviour and patch for a fix to
something already released. It moves once per merged PR, not once per push.
-->
