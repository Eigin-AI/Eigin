# Initiative

Agreed notifications appear in **For you** and, when enabled, on the device. Both open the same chat.

| Kind | Tool | Opening it |
| --- | --- | --- |
| Recurring initiative | `set_initiatives` | Starts current work on an intent |
| Reflection | `background_notify` | Shows a useful observation or completed work and briefing; waits for a reply |
| One-off follow-up | `follow_up` | Shows the prepared message and briefing in the original space; waits for a reply |

## Scheduling

Use daily or weekly schedules for recurring initiatives. Get consent before changing agreed times.

- **Manage:** check with `list_initiatives`; stop with `cancel_initiative`, intent detail, or by resolving the intent.
- **Time zone:** recurring times follow the device’s zone when the app is active. Until then, installed notifications keep their scheduled zone.
- **Delivery:** saving works without notification permission. Check the tool result for delivery status.

### Notification spacing

New or changed times are checked across all agents and spaces on the device.

| Distance from another notification | Result |
| --- | --- |
| Less than 5 minutes | Rejected without saving |
| 5 to 15 minutes | Scheduled with a warning |
| More than 15 minutes | Scheduled |

Saved future messages reserve their times even when system delivery is unavailable. Existing schedules stay unchanged; requested times are never shifted automatically.

## For you

The avatar in either chat header opens the newest five due messages across the agent’s spaces.

- Keep only the latest unopened occurrence of each recurring initiative.
- Opening, dismissing, or overflow removes a message permanently; older items never refill the list.
- Dismissing leaves future recurrence active. Discovery runs in the foreground; recurring work starts when opened.
- Tracking begins at upgrade without historical backfill. Legacy follow-ups with unknown due times remain notification-only.

## Background work

With a cloud model selected and permission granted, the agent reflects on recent activity, prepares context, and maintains knowledge. Balanced reaches out selectively; proactive works and shares useful observations more often. Reactive keeps explicitly agreed notifications while disabling background work.

Reflections focus on unscheduled goals and recent conversations, avoiding topics covered by prior or upcoming outreach. With balanced or proactive enabled, the selected model may receive excerpts from multiple accessible chats, saved knowledge, goals, and outreach history without an active chat. They use only tools already allowed in the background and can stay silent. Saved reflections appear in For you when due, even without notification permission.

Preparation uses authorized read tools and saves scoped findings for later conversations. Maintenance consolidates knowledge and may ask for clarification.
