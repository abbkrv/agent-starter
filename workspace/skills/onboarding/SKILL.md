---
name: onboarding
description: First-run personalisation. Use on the operator's FIRST message when core/USER.md still has the NOT_YET_ONBOARDED marker, or when the operator says "onboard me", "set up my agent", "personalise", "заполни профиль".
---

# onboarding

Get to know a brand-new operator in a short, friendly chat and fill in their
profile (`core/USER.md`) yourself — so they never have to edit files by hand.

## When to use

- The operator's FIRST real message, if `core/USER.md` still contains the
  `NOT_YET_ONBOARDED` marker (installer defaults, profile not filled yet).
- The operator asks to (re)do onboarding after a role/timezone change.

## What to do

1. Read `core/USER.md` (name + Telegram ID are already filled by the installer).
2. Introduce yourself in ONE line, then ask 3-4 short questions conversationally
   (one at a time, do not dump a survey):
   - Чем ты занимаешься / над чем работаешь? (роль)
   - На каком языке общаться и на «ты» или на «вы»?
   - 2-3 вещи о том, как тебе удобнее, чтобы я работал (стиль, детализация)?
   - (опц.) Часовой пояс, если важны напоминания по времени.
3. Write the answers into `core/USER.md`, replacing the placeholder sections
   (Role / What the agent helps with / Working preferences / language / addressing).
4. **Remove the `NOT_YET_ONBOARDED` marker line** from the top of USER.md so this
   doesn't trigger again.
5. Confirm briefly: «Настроил под тебя. Профиль можно поправить в любой момент —
   просто скажи мне». Then continue with whatever they originally wanted.

## Rules

- Keep it SHORT — 2 minutes, not a 20-question survey. People want to get productive.
- Be warm; the operator may not be technical. No jargon.
- If the operator ignores the questions and just gives a task — do the task first,
  gather the profile naturally over the next messages, fill USER.md when you know enough.
- Never invent facts about the operator. Only write what they told you.

## Files touched

- `core/USER.md`   — fill in the profile, remove the marker.
- `core/MEMORY.md` — optionally append durable preferences under `## Onboarding`.
