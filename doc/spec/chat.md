# Technical requirements: chat

Status: draft, 2026-11-14.
Component: the `chat` module of `retromud-gui`. See `doc/design.md`.

## 1. Purpose

RetroMUD has many chat channels. A player listens on several channels at the same time. This document states what the `chat` module must do. The goal is that the player can read each channel and still see the main game text.

## 2. Terms

- Channel: a named stream of messages. Examples are `retro` and `fighter`.
- Group: a set of channels that the GUI shows together. All six world channels form one group.
- Tab: one view in the chat panel. A tab shows one group, one channel, or all lines.
- Rule: one entry in the routing table. A rule says how to find a chat line and which channel the line belongs to.
- Routing: the work of sending each chat line to the right tab.
- Speaker: the player or character who sends a message.
- Decoration: the text between `<` and `>` in a guild message. Each guild has its own decoration.
- Continuation line: a line that continues the message above it. In live output it starts with 5 to 7 spaces. Most start with 6.
- Action: a message in which the player tells what the character does. The player writes `*` around the text to make one.
- Prompt: the status line that the game sends after each output block. It shows the health values of the character.
- History block: the output of a history command such as `retro last`.
- Event: a named message between two scripts. One script raises it. Other scripts listen for it.
- Mortal: a normal player character. A mortal cannot use the wizard channels.
- Settings file: a file in the Mudlet profile folder. The player can edit it. It changes the default settings of the module.

## 3. Scope

The first version includes these items:

1. Finding chat lines in the game output.
2. Routing each chat line to a tab.
3. Showing the lines in a panel with tabs.
4. Marking tabs that have unread lines.
5. Settings for the items above.

The first version does not include these items:

1. Sending chat. The player uses the normal command line.
2. Sending history commands for the player. The module only handles the output that the player requests.
3. Saving chat to a file.
4. Sound and desktop notifications.
5. GMCP. RetroMUD does not send it.

## 4. Requirements

Each requirement has an identifier. A test or a manual check must exist for each requirement. See section 7.

### 4.1 Finding lines

CHAT-001. The module must find a chat line only when a rule matches it. A word in brackets is not enough. Combat and status text also uses brackets. Examples are `[hit]`, `[hits]`, `[misses]`, `[beating]`, and `[undead]`.

CHAT-002. The module must support these line forms. Appendix A has a sample for each form.

1. Player channel: `Name [channel]: text`. The brackets depend on the speaker and can be `[ ]`, `{ }`, or `< >`. See CHAT-017. Example: `Name {retro}: text`.
2. Channel action: `[channel]: Name action text`. The three bracket types apply. Example: `<retro>: Name hides`.
3. Guild channel: `Name < decoration > text`. Appendix C lists the decorations.
4. Guild channel action: `< decoration > Name text`. The decoration comes first.
5. World announcement: `[world] text`. It has no speaker.
6. Party chat: `Name (Party): text`.
7. System notice: `[info] text` and `[alert] text`. The game writes these lines. No player sends them. The text is free-form and does not need to hold a player name. The form `[alert]` is an assumption. See section 8.
8. Tell from a player: `Name telepathically contacts you with 'text'`.

CHAT-003. If a line follows a chat line and starts with 5 to 7 spaces, the line must go to the channel of the line above. The module must stop at the first line that does not match. This rule does not apply to history blocks. See CHAT-070. The sample logs show these indents: 6 spaces in most messages, 5 spaces in one message, and 7 spaces in `[info]` lines.

CHAT-003a. A line of drawn map art can start with the same spaces. If less than half of the non-space characters of the line are letters or digits, the module must not treat the line as a continuation line. The indent range and the ratio must be settings in the rules table.

CHAT-004. If a line has the guild form but its decoration is not in the table, the line must go to the Guild tab. The module must not drop the line. A decoration counts as a decoration only if it has at least 3 characters and at least one symbol. This keeps plain text such as `a < b > c` out of the Guild tab.

CHAT-005. The module must look at every line. Chat lines arrive between other output, with no blank line before or after them.

CHAT-006. The module must not match the command that the player typed. If the typed command appears after the prompt in Mudlet (Appendix A.8), the module must ignore all text after the `>` of the prompt.

### 4.2 Rules as data

CHAT-010. The routing rules must be a Lua table in a settings module. The code that applies the rules must not contain a pattern. To add a channel, the developer adds one table entry.

CHAT-011. Each rule must have an identifier, a form, a Lua pattern, a channel name, and a group name.

CHAT-012. The guild decorations must be a table that maps the decoration text to a channel name. Appendix C lists the 16 known decorations. Example: `(=Fighter=)` maps to `fighter`.

CHAT-013. The player must be able to add or change rules in the settings file, without a change to the package. The settings file replaces a default rule that has the same identifier. If a rule has an error, the module must ignore the rule and show one message that names it.

CHAT-014. The module must compare a decoration as plain text, with `string.find(line, decoration, init, true)`. It must not use the decoration as a Lua pattern. Decorations contain these characters: `^ % - [ ] ( ) $ < >`.

CHAT-015. The table must store each decoration without spaces at its ends. The match must allow spaces between the decoration and the closing `>`. Some decorations have two spaces there.

CHAT-016. In the normal form, the speaker is the text before ` < `. A speaker name can have spaces, a title, and commas. It is not one word. In the action form, the name and the action cannot be split safely. The speaker is `nil`, and the text holds the name and the action together.

CHAT-017. The module must accept the three bracket types `[ ]`, `{ }`, and `< >` around a channel name. This applies to the player-channel form and to the action form. The opening and closing bracket must form a pair. The module must put the bracket type in the field `rank` of the event `rmgui.onChat`. The meaning of each type is not confirmed. See section 8.

CHAT-018. System notices (`[info]` and `[alert]`) have no speaker. The module must not try to read a name from them. The field `speaker` in `rmgui.onChat` must be `nil`. If a player name is in the text, the module must leave it there.

### 4.3 Groups and tabs

CHAT-020. The module must offer these default tabs:

| Tab | Content |
|---|---|
| All | Every chat line |
| Chat | `chat`, `retro`, `sales`, `mentor` |
| World | The six world channels in one group: `welstar`, `wysoom`, `raji`, `sosel`, `crypt`, `perdow` |
| Party | Party chat |
| Info | Two groups on one tab: `info` (the `[info]` lines and the `inform` channel) and `alert` (the `alert` channel) |
| Wizard | `wiz` and `arch`. See CHAT-025 |
| Guild | All guild channels |
| Tells | Tells from players |

CHAT-021. The six world channels must be one group. The player must be able to split the group into six tabs in the settings file. The default is one group.

CHAT-022. In the settings file, the player must be able to change which channels belong to which tab. The player must also be able to add a tab and to hide a tab.

CHAT-023. In a tab that holds a group, each line must show its channel name. In a tab that holds one channel, the module does not need to show it.

CHAT-024. A line can appear on two tabs. It appears on `All` and on its own tab.

CHAT-025. A mortal never receives `wiz` or `arch` lines. The module must create the Wizard tab when the first such line arrives. The module must keep the tab until the session ends. A mortal never sees an empty Wizard tab.

### 4.4 Display

CHAT-030. The chat panel must be an `Adjustable.Container` with tabs. It must work as a column and as a floating panel. See `doc/design.md`.

CHAT-031. If a tab has unread lines, the tab must show a mark. The mark can be a count. The mark must disappear when the player opens the tab.

CHAT-032. A line must keep the colors that the game sent. The background must come from the theme that the player picked. See "Theming" in `doc/design.md`.

CHAT-033. Each tab must keep at most N lines. The default for N is 2000. The player can change N in the settings file. When the limit is reached, the module removes the oldest line first.

CHAT-034. A wrapped message must appear as one block. Its continuation lines must stay in the same tab.

### 4.5 Main window

CHAT-040. A setting must decide if a chat line also stays in the main game window. The setting must exist for each tab group. The default is not decided. See section 8.

### 4.6 Events

CHAT-050. For each message that the module finds, the module must raise the event `rmgui.onChat`. The arguments are the channel name, the group name, the speaker name (or `nil`), the bracket type, and the text with its continuation lines.

CHAT-051. The module must not call the mapper. The two packages stay independent.

### 4.7 History blocks

CHAT-070. The module must find the header `Displaying last <channel>:`. All lines from the header to the next prompt are one history block. In a history block, each message starts with `[epoch] [hh:mm:ss]`, and wrapped lines have no indent.

CHAT-071. The module must not send history lines to the tabs as live messages. The lines stay in the main window. This prevents copies of old messages.

CHAT-072. A chat line can start with the prefix `[epoch] [hh:mm:ss]`. The module must remove the prefix before it applies the rules. The module must keep the time. A later history feature can use it. See open question 10.

### 4.8 Non-functional

CHAT-060. The module must not slow the game. On a typical desktop computer, the module must match one line in less than 1 ms on average. We measure this with the sample logs.

CHAT-061. The module must work when the mapper is not installed.

CHAT-062. The module must not add names to the global namespace. It keeps all state in the table `rmgui.chat`.

CHAT-063. When the package is uninstalled, the module must remove its triggers, its handlers, and its panels. See "Install and uninstall" in `doc/design.md`.

CHAT-064. The player must be able to use the tab bar with the keyboard. The tab bar and the marks must have enough contrast in all five theme presets.

## 5. Interfaces

1. Input: lines of game text. Mudlet triggers deliver every line.
2. Output: text in the chat panel and the event `rmgui.onChat`.
3. Settings: the routing rules, the guild decoration table, the tab list, the line limit, and the main-window setting. All of them are in the settings file. See "Saved settings" in `doc/design.md`.

## 6. Constraints

1. The player can change the prompt format. The module must not depend on it.
2. We have samples for few channels. See Appendix B. The default rules cover only those channels. The catch-all rule in CHAT-004 protects the other guild channels.
3. Before we use a Mudlet function, we must make sure in Mudlet that it works as we expect. This applies to the functions that give the text and the colors of a line, and to the function that copies a line.
4. A chat library named EMCO exists. We have not read its license or its API. If we use it, the requirements in this document still apply.

## 7. Verification

1. Unit tests: the rule engine is pure Lua and does not use Geyser. They are in `test/chat_engine_test.lua`. Run `./test/run.sh`, or `COVER=1 lua test/chat_engine_test.lua` to list the engine lines that no test ran. Each test gives sample lines to the engine. It makes sure that the channel, the group, and the speaker are correct. The sample lines in Appendix A and C are the first tests.
2. Replay test: run the sample logs through the rule engine. Count the lines by channel and compare the counts with Appendix B. No line that is not chat can match. See CHAT-001.
3. Continuation test: a message with continuation lines must stay in one tab. See CHAT-003 and CHAT-034.
4. Manual test in Mudlet: CHAT-006, CHAT-030, CHAT-031, CHAT-032, CHAT-040, and CHAT-064.
5. Performance test: time the rule engine on the largest sample log. See CHAT-060.

## 8. Open questions

1. Which action forms exist? We have the action form for `chat` and for the Abjurer guild only. Does every guild use `< decoration > Name text` when the player writes `*...*`?
2. Does an `alert` line start with `[alert]`? The player says that `alert` works like `info`. We have no sample line. If both channels use the tag `[info]`, the module cannot tell the two groups apart.
3. Which other tell verbs exist? What does the own tell of the player look like? What does a reply look like?
4. What do the bracket types mean? The same history block shows `[retro]`, `{retro}`, and `<retro>`. The type `< >` probably marks an immortal. What does `{ }` mark? Which speaker types exist?
5. What does the prefix `:*:` mean in a line such as `:*: Aldric cackles at you.`? Is it a social or a channel?
6. Does the action form apply to every channel with each of the three bracket types?
7. Does the typed command of the player appear after the prompt in Mudlet? See CHAT-006.
8. What is the default for CHAT-040? Many players want chat in both places.
9. Does a character that is not in a guild see the messages of that guild? The samples show only the own messages of the player.
10. Must the module fill a tab from history when the player connects? It could send `<channel> last`. This would show recent messages in a new session. It would also send commands to the game, so it needs a setting and a limit.
12. Does the indent of a continuation line change with the terminal width? All logs that we have use the width 80. At a narrower or wider width, the game can use another indent, or no indent. The module cannot find a continuation line that has no indent.
11. The channel list shows only `welstar` and `perdow` of the six world channels. Do `wysoom`, `raji`, `sosel`, and `crypt` exist as channels that the player can switch on? Or are they announcements only? We have no sample line for them.

## Appendix A: observed line forms

All names and message text in these samples are made up. They show the shape of each line. The game strings that belong to the format are real. Examples are `Displaying last retro:`, `Nothing to show.`, and `telepathically contacts you with`. The real sample logs are in `retromud-mudlet-mapper/tmp/`. They are not part of this repository.

1. Player channel: `Aldric [mentor]: Welcome to the game!`
2. Wrapped message: the line after `Aldric [mentor]: The trick with the first room is to look at` starts with 6 spaces and holds `the sign twice.`
3. Channel action (the player typed `chat *waves hello*`): `<chat>: Aldric waves hello`
4. Guild channel, Fighter: `Aldric < (=Fighter=) > one two three`
5. Guild channel, Fallen: `Aldric < (FALLEN) =}----  > one two three`
6. Guild channel, Merchant: `Aldric < $$ MERCHANT $$ : > one two three`
   Guild channel action (the player typed `abjurer say *waves hello*`): `< ^abjurer^ > Aldric waves hello`
   Wrapped guild message: the line after `Aldric < [BARD] [===]---#  > this is a longer message that wraps onto` starts with 6 spaces and holds `a second line`.
7. Tell: `Mirel telepathically contacts you with 'a short message that wraps onto`. The next line starts with 6 spaces and holds `the next line.'`
8. Prompt with the typed command after it: `Hp:120/120 Sp:80/95 Ep:60/60 Exp:5000 >fighter say one two three`
9. World announcement: `[welstar] A loud horn sounds across the`. The next line starts with 6 spaces and holds `world as a great beast falls!`
10. Party chat: `Aldric (Party): ready`
11. System notice: `[info] Aldric goes linkdead`
    System notice about a game event: `[info] Aldric has lit a torch in the old tower.` This line follows a prompt line directly. So `[info]` carries game events and link notices. The game writes the text. It is free-form.
12. Channel history command: `fighter last`. The reply is `Nothing to show.`
13. Text that looks like a channel but is not: `You [hit]: 120`, and lines that start with `[beating]`.
14. Wizard channel: `Aldric <wiz>: test message`. The `arch` channel has the same form: `Aldric <arch>: test message`. In history output, the same line is `[1700000100] [10:15:00] Aldric <wiz>: test message`. The wrapped lines have no indent.
15. History block: the header `Displaying last retro:`, then lines such as these:
    - `[1700000200] [10:16:40] Aldric {retro}: one two three`
    - `[1700000210] [10:16:50] Mirel [retro]: four five six`
    - `[1700000220] [10:17:00] Bran <retro>: seven eight nine`

    Action lines in history are `[1700000300] [10:18:20] <retro>: Bran waves` and `[1700000310] [10:18:30] {retro}: Aldric waves`.
16. Tell with several continuation lines: the first line holds `Mirel telepathically contacts you with 'a long message`. Each of the next lines starts with 6 spaces. The last line ends with `'`.

## Appendix B: counts in the sample logs

We counted on 2026-11-14 in 11 log files. The files hold about 8 MB in all.

| Form | Count |
|---|---|
| `Name [retro]:` | 211 |
| `Name [sales]:` | 10 |
| `Name [mentor]:` | 4 |
| `Name [chat]:` | 1 |
| `Name <channel>:` (all in history output, with a timestamp prefix) | 11 |
| `[info]` at the start of a line | 214 |
| `(Party)` | 3070 |
| `[welstar]` or `[perdow]` at the start of a line | 2 |
| `You [hit]:` | 298 |

The logs hold no guild message. They hold no `alert` line and no `inform` line. The decorations in Appendix C and the `wiz` form come from test messages that the player sent on 2026-11-14.

## Appendix C: guild decorations

The player confirmed on 2026-11-14 that these 16 channels are all the guild channels. The table shows each decoration without spaces at its ends. All 16 come from test messages that the player sent. All use the normal form `Name < decoration > text`, except Abjurer. The player wrote that one as an action.

| Channel | Decoration |
|---|---|
| abjurer | `^abjurer^` |
| alchemist | `[alchemist]:` |
| assassin | `-Assassin-` |
| bard | `[BARD] [===]---#` |
| biomancer | `<>biomancer<>:` |
| cultist | `(Cultist):` |
| druid | `',~~ DRUID ~~,'` |
| fallen | `(FALLEN) =}----` |
| fighter | `(=Fighter=)` |
| jomsviking | `__[Jomsviking]__)` |
| merchant | `$$ MERCHANT $$ :` |
| monk | `69 MONK 69:` |
| paladin | `{Paladin}` |
| psionicist | `{Psionicist}` |
| ranger | `>>-RANGER->` |
| templar | `[TEMPLAR]:` |

These 16 lines are the first test cases for the rule engine. See section 7.
