# Initiative

An **initiative** is an agreed recurring invitation to work on an intent. Opening it starts current work in a new chat; repeated taps reopen that chat.

## Scheduling

Use `set_initiatives` for daily or weekly invitations with wording that fits the task across repeated occurrences. Check agreements with `list_initiatives` and stop them with `cancel_initiative`. Times follow the device's time zone. Same-time tasks combine within one agent and space; changing agreed times requires consent.

Scheduling requires notification permission. The tool reports saved agreements and delivery status separately. Cancel through the tool or intent detail; resolving an intent also cancels its invitations. Missed occurrences never replay automatically. Interrupted work can be resumed explicitly in its chat.

## Background work

With permission, the agent prepares for future conversations and maintains its knowledge. Balanced runs occasionally; proactive runs more often. Reactive disables background work while keeping explicitly agreed initiatives.

Preparation gathers context for current intents and upcoming initiatives using authorized read tools. It saves scoped findings with sources and observation times. Conversations reuse those findings and prior initiative outputs, checking current facts when needed. Scheduled invitations work independently of preparation.

Maintenance consolidates knowledge and may ask for clarification.

## One-off follow-ups

`follow_up` delivers a message prepared now. Opening it shows the message and briefing; it does not start new work.
