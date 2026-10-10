# Production keyboard cursor repair

Online hand updates now reset a cursor pointing beyond the new hand to its
first card. Valid positions stay in place, matching the existing solo path.

The original production game plays 3H, then the last displayed card AD and
nominates clubs. At turn 4 the hand has five cards but the cursor remains 5.
Space selects the invisible removed slot and P sends nothing. The expanded
ROM-backed regression fails with `cursor outside replacement hand: cursor=5,
count=5` before the fix. It passes afterwards, including actual Space/P frame
construction, retained valid positions, appended draws and empty hands.

[Before](baseline-cursor.png) and [after](fixed-cursor.png) show the same hand
and turn. `make -B all test reference-parity`, `make ui-test`, codec conformance
and reconnect hydration pass. The fixture-pin tests deliberately reject missing
and altered pins; their diagnostic errors precede three passing tests.

The repaired 7,740-byte production PRG completes a local seed-2 game against
one Go bot through Ultimate emulation. Both test flags are zero. Inputs use
the actual chooser, host field, Right, Space, P, D and C keys. The run exercises
ordinary/penalty draws, a two-King play, Ace nomination, a Black Jack countered
by the bot, Seven and Queen plays. At turn 37 the C64 holds four cards and
correctly shows [You finished last](final-result.png). Space reaches the
[chooser](returned-menu.png), clears game/hand state and discards the token.
The host records `Game finished`; both owned processes are stopped.

The first repaired attempt stops at turn 10 because the emulator rejects its
advertised `Left` key. The successful repeat uses the same PRG and Right-key
wraparound. Earlier MCP loader/capture probes and that failure remain in the
local raw evidence. No emulator source or game memory was changed. Script mode
loads the real production program and exports its executed opening chooser;
MCP restores that pre-network state because its `--load` path does not import
PRGs. No snapshot containing ROM state is published here.

[Manifest](manifest.json) records source/artifact hashes and original paths.
This closes one production online keyboard game and result-to-menu journey.
The prior native iPhone/Android/C64 games retain their original C64 artifact.
Physical hardware, user-port keyboard play, a native mobile peer, Left-key
delivery and unexercised controls remain outside this run.
