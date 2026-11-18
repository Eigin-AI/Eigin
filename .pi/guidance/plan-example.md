# Plan: Schedule follow-ups from a conversation

_This example is reconstructed from completed Eigin work. It describes the proposal at the time; code references are local starting points, not a description of the current implementation._

## The problem

I ask my agent to follow up tomorrow. It agrees (or creates an intent), but I might hear nothing until I open the app and message it again.

I want a message at the agreed time, without having to prompt the agent, and enough context to continue when I open it.

## The idea

Prepare the message when we agree on the follow-up and let iOS deliver a notification. This avoids relying on background execution to run the agent later.

The agent prepares a title, message, delivery time, and briefing. After user approval, save these locally and try to schedule the notification. If delivery cannot be scheduled, keep the item in “For you” and explain the outcome. Tapping it opens a conversation with the saved briefing and message.

In this approach, we trade freshness for reliability by relying on prepared one-off messages. Follow-ups that require new work, recurring tasks, and calendar events belong in their existing workflows.

## Implementation

### System context

`AgentInitiativeRequest` already stores notification messages and briefings. See its [original schema](../../src/eigin_ios/Sources/Core/Persistence/SchemaVersions/SchemaV1/SchemaV1+AgentInitiativeRequest.swift). The [notification delegate](../../src/eigin_ios/Sources/App/Notifications.swift) opens them by request ID. We'll reuse that path.

Add a due time, optional space, conversation ID, and opened/dismissed/discarded state to the record. Preserve the behavior of older records without a due time.

### New components

- **`FollowUpTool`** in `Agent/Tools`: validates inputs and calls an injected scheduler. Register it in [`AgentToolKit`](../../src/eigin_ios/Sources/Agent/Tools/AgentToolKit.swift), with approval required. Keep it out of background tool sets.
- **`FollowUpScheduler`** in `Agent/Services`: saves the request and schedules delivery. Extract shared notification work from [`BackgroundPromptScheduler`](../../src/eigin_ios/Sources/Agent/Services/BackgroundPromptScheduler.swift) and wire the scheduler through the existing [service factories](../../src/eigin_ios/Sources/App/Container+Services.swift).
- **`WaitingMessageStore`** in `Agent/Intent/Services`: lists due requests and opens their conversations. Notification taps and “For you” use this same opening path.

### Component interactions

The tool returns both the saved request ID and the delivery outcome, so the agent can accurately explain what happened.

```text
FollowUpTool.execute(title, message, summary, deliver_at)
  -> scheduler.schedule(agent, space?, content, due_at, can_prompt_user)
  -> { request_id, delivery_status }

WaitingMessageStore.due(agent, now) -> saved follow-ups
WaitingMessageStore.open(request_id) -> conversation_id
```

Persist before scheduling so a notification always points to a saved request. Retain that request when delivery is unavailable.

```text
after user approval:
  validate required text and a future delivery time
  save the request; on failure, stop without scheduling
  check notification permission and capacity
  if unavailable: return saved + reason
  prepare the notification with the saved request ID
  recheck that the request is pending and the time is valid
  await notification-center acceptance
  report saved + delivery outcome; retain the item on delivery failure
```

Both entry points use the same opening operation. Serialize opening so repeated taps cannot create duplicate conversations.

```text
on notification tap or opening a due item:
  load the request and validate its agent/space
  return its existing conversation if already opened
  reject dismissed or discarded requests
  create a conversation with the saved briefing and message
  save the conversation and the request's opened state together
  navigate to it and clear handled notifications
```

## Risks and limits

- **Time:** use local time when no timezone is supplied; honor explicit offsets. Clarify ambiguous requests.
- **Delays:** permission prompts can outlast the requested time. Keep an overdue item available in the app without scheduling a stale notification.
- **Delivery:** iOS acceptance does not guarantee an alert at an exact instant. Device settings can affect presentation.

## Evaluation

Inject the clock, parser calendar, authorization, notification preparation, and delivery. Tests can advance time, deny permission, fail delivery, or hold scheduling open. Use real SwiftData in an isolated test container, plus a read-only store for save failures.

Check these outcomes:

- [ ] Declining approval saves nothing and requests no notification permission.
- [ ] Success saves the content, due time, and scope. The notification uses that request ID. The tool waits for scheduling acceptance before reporting success.
- [ ] Denied permission, exhausted capacity, or delivery failure leaves a saved item available when due, with an accurate delivery status.
- [ ] Failed persistence prevents scheduling.
- [ ] Invalid or past times are rejected. Local and explicit-offset times resolve correctly; a deadline passing during preparation prevents scheduling.
- [ ] Both opening paths produce the same conversation with the right briefing and scope. Repeated taps reuse it; dismissed items stay closed.

A device walkthrough checks system presentation: schedule, close the app, tap the notification, and inspect the conversation. Repeat with notifications disabled, opening through “For you.”

Prepared messages are suitable if this walkthrough provides enough context to continue. If follow-ups commonly need fresh information at delivery time, reconsider the prepared-message scope before extending it.

## Implementation steps

1. **Tool and validation.** Add inputs, time parsing, and approval behavior. Test against an injected scheduler.
2. **Persistence and scheduling.** Extend the saved record and add the scheduler. Cover success and failure outcomes with controlled notification dependencies.
3. **Opening and navigation.** Add the waiting-message store and connect both entry points. Test context, scope, and repeated opening.

These can be separate issues. Agree the scheduler contract and saved-record shape first, then connect the pieces and run the device check.

## Decision log

1. Reconstructed example: prepare one-off messages at approval time to avoid relying on background agent execution; retain saved items when notification delivery is unavailable.
