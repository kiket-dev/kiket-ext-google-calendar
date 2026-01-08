# Google Calendar Extension

Sync Google Calendar events to Kiket's team capacity planning. Automatically imports events and updates team member availability.

## Features

- **Automatic Sync**: Periodically imports calendar events to capacity planning
- **Multiple Calendars**: Sync from multiple Google Calendars per user
- **Event Type Mapping**: Automatically categorize events (PTO, meetings, focus time, etc.)
- **Timezone Support**: Handles timezone-aware events correctly
- **Blocking Detection**: Identifies events that block availability
- **Health Monitoring**: Alerts when sync issues occur

## Requirements

- Kiket Platform v1.0+
- [Google OAuth Extension](https://github.com/kiket-dev/kiket-ext-google-oauth) (installed automatically as dependency)
- Google account with Calendar access

## Installation

1. Install the extension from the Kiket Marketplace or via CLI:
   ```bash
   kiket extensions install google-calendar
   ```

2. The Google OAuth extension will be installed automatically if not present

3. Connect your Google account when prompted

## Setup

### 1. Connect Google Account

If you haven't already connected your Google account:

1. Go to **Settings > Connected Accounts**
2. Click **Connect** next to Google
3. Authorize calendar access in the popup

### 2. Select Calendars to Sync

1. Go to **Capacity > External Calendars**
2. Click **Add Calendar > Google Calendar**
3. Select which calendars to sync
4. Configure sync settings

## Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `default_sync_interval` | 60 min | How often to sync calendar events |
| `sync_window_days` | 180 days | How far ahead to sync events |
| `include_declined` | false | Include events you've declined |
| `include_tentative` | true | Include tentatively accepted events |

### Event Type Mapping

Events are automatically categorized based on keywords in the title:

| Event Type | Keywords |
|------------|----------|
| Holiday | "holiday", "bank holiday" |
| PTO | "vacation", "pto", "out of office", "ooo" |
| Travel | "travel", "flight", "trip" |
| Focus | "focus", "deep work", "heads down" |
| Training | "training", "learning", "workshop" |

You can customize the mapping in extension settings.

## Usage

### Automatic Sync

Once configured, the extension automatically syncs on the configured interval. Events appear in:
- **Capacity Calendar**: Visual calendar view
- **User Availability**: Affects capacity calculations
- **AI Recommendations**: Considered in load balancing

### Manual Sync

Trigger a manual sync via:
- **Command Palette**: Search for "Sync Google Calendar"
- **Capacity UI**: Click the refresh button on your calendar feed

### Commands

| Command | Description |
|---------|-------------|
| `googleCalendar.sync` | Manually trigger calendar sync |
| `googleCalendar.listCalendars` | View available Google Calendars |

## Required Scopes

This extension requires the following Google OAuth scopes:

| Scope | Purpose |
|-------|---------|
| `calendar.readonly` | List available calendars |
| `calendar.events.readonly` | Read calendar events |

These scopes are automatically requested when you connect your Google account.

## Capacity Integration

Synced events affect capacity planning:

- **Blocking Events**: Reduce available hours
- **All-Day Events**: Mark entire day as unavailable
- **Tentative Events**: Optionally reduce capacity
- **Recurring Events**: Each occurrence synced separately

## Troubleshooting

### Events not syncing
1. Check connection status in **Settings > Connected Accounts**
2. Verify the calendar is selected in **Capacity > External Calendars**
3. Check feed health status for errors

### Wrong timezone
1. Verify your Kiket timezone in **Settings > Preferences**
2. Check calendar timezone in Google Calendar settings

### Missing events
- Private events may be hidden depending on your Google Calendar sharing settings
- Check if the event is within the sync window (default: 180 days)

### "Calendar feed unhealthy" warning
- The extension monitors sync health
- Alerts are sent after 12+ hours of failures
- Check Google account connection and re-authorize if needed

## Health Monitoring

The extension includes health monitoring:
- Tracks consecutive sync failures
- Status: Healthy → Degraded (3 failures) → Unhealthy (12+ hours)
- Sends notifications when feeds become unhealthy

## Security

- Calendar data is read-only (no write access requested)
- Events are stored encrypted in Kiket's database
- OAuth tokens managed by Google OAuth extension
- Private event details can be excluded

## Related Extensions

- [Google OAuth](https://github.com/kiket-dev/kiket-ext-google-oauth) - Required for authentication
- [Microsoft Calendar](https://github.com/kiket-dev/kiket-ext-microsoft-calendar) - Alternative for Outlook users

## Support

- [Documentation](https://docs.kiket.dev/integrations/google-calendar)
- [GitHub Issues](https://github.com/kiket-dev/kiket-ext-google-calendar/issues)

## License

MIT License - see [LICENSE](LICENSE) for details.
