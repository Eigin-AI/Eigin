# Initiative

Agreed notifications appear in **For you** and, when enabled, on the device. Both open the same chat.

| Kind | Tool | Opening it |
| --- | --- | --- |
| Recurring initiative | `set_initiatives` | Starts current work on an intent |
| One-off follow-up | `follow_up` | Shows the prepared message and briefing in the original space; waits for a reply |

## Scheduling

- Use daily or weekly schedules for recurring initiatives. Changing agreed times requires consent.
- Check agreements with `list_initiatives`; stop them with `cancel_initiative` or intent detail. Resolving an intent also cancels its initiatives.
- Recurring times follow the device’s time zone when the app is active. Installed notifications keep their scheduled zone until then.
- Saving works without notification permission. Check tool results for scheduling status.

## For you

The avatar in either chat header opens the newest five due messages across the agent’s spaces.

- Keep only the latest unopened occurrence of each recurring initiative.
- Opening, dismissing, or overflow removes a message permanently; older items never refill the list.
- Dismissing leaves future recurrence active. Discovery runs in the foreground; recurring work starts when opened.
- Tracking begins at upgrade without historical backfill. Legacy follow-ups with unknown due times remain notification-only.

## Background work

With permission, the agent prepares context and maintains knowledge. Balanced runs occasionally; proactive runs more often. Reactive keeps explicitly agreed notifications while disabling background work.

Preparation uses authorized read tools and saves scoped findings for later conversations. Maintenance consolidates knowledge and may ask for clarification.
