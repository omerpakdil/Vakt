You are building a native iOS app called “Vakt”.

Core product idea:
Vakt helps Muslims start the five daily prayers on time by joining live, silent “prayer-start rows” with others.

This is NOT a Quran room app.
This is NOT a post-prayer reflection app.
This is NOT a generic prayer tracker.
This is NOT an app blocker.
This is NOT a social network.

The core mechanic is:
When prayer time approaches, users join a live silent Saf, see others getting ready, update their own preparation status, then put the phone away and start salah.

Product positioning:
“When it’s time, stand together.”
“Start salah with others.”
“No camera. No voice. No chat. Just presence.”

Build this as a native iOS MVP using:
- Swift
- SwiftUI
- iOS 17+ minimum target
- Swift Concurrency async/await
- Observation framework or ObservableObject where appropriate
- Supabase Swift SDK for Auth, Database, and Realtime
- CoreLocation for location-based prayer times
- UserNotifications for local prayer notifications
- ActivityKit for Live Activities
- WidgetKit for Home Screen / Lock Screen widgets
- AppIntents for widget and system actions
- SwiftData or local persistence for cached user preferences and prayer times
- Clean MVVM or lightweight feature-based architecture
- Native iOS navigation using NavigationStack and TabView
- Dark mode first
- English UI only

The app must feel native, premium, calm, fast, and privacy-respecting.

Do not build with React Native, Expo, Flutter, UIKit-first architecture, web views, or cross-platform abstractions.

Do not overbuild.
Do not add:
- Quran reader
- Hadith feed
- dua library
- comments
- chat
- voice rooms
- camera
- livestream
- public profiles
- followers
- rankings
- badges
- coins
- guilt-based streaks
- proof of prayer
- location proof
- camera proof
- mosque check-in proof
- Islamic content feed

The app is about helping users START salah, not proving that they prayed.

--------------------------------------------
1. MAIN PRODUCT CONCEPT
--------------------------------------------

The app revolves around the five daily prayer lobbies:

- Fajr
- Dhuhr
- Asr
- Maghrib
- Isha

Each prayer has a live Saf lobby.

A Saf lobby opens before the prayer time and remains active shortly after prayer time begins.

Users can join the lobby and set one of these statuses:

- Getting up
- Making wudu
- Finding a place
- Ready
- Praying

Users see live aggregated counts and soft anonymous participant dots.

No chat.
No voice.
No camera.
No pressure.
No public profile.

The emotional goal:
The user should feel:
“I’m not starting salah alone. Others are standing too.”

--------------------------------------------
2. NATIVE iOS ADVANTAGE
--------------------------------------------

Use native iOS surfaces deeply.

The app should not require the user to open the app every time.

Use:

A. Live Activities
When a Saf window opens, the user can start a Live Activity for the current prayer.

Live Activity should show:
- Prayer name
- countdown to prayer time or “Open now”
- number of people in the Saf
- user’s current status
- quick status buttons if possible through App Intents / deep links
- calm copy such as “Your Saf is getting ready.”

Dynamic Island compact state:
- prayer name
- small countdown
- small live count

Dynamic Island expanded state:
- prayer name
- time remaining
- live Saf count
- status summary
- action: Open Vakt

Lock Screen Live Activity:
- “Dhuhr Saf”
- “Starts in 04:31”
- “126 people preparing”
- status chips:
  - Getting up
  - Wudu
  - Ready
  - Start Salah

If interactive Live Activity actions are too much for MVP, deep-link into the app to update status.

B. Widgets
Create a small Home Screen widget:
- Next prayer
- time remaining
- Saf opens in X
- live count if available

Create a medium widget:
- today’s five prayer times
- next active Saf
- join button/deep link

Create Lock Screen widget:
- next prayer countdown
- simple symbol
- deep link to current Saf

C. App Intents
Create App Intents for:
- JoinCurrentSafIntent
- SetPrayerStatusIntent
- StartSalahIntent
- OpenNextPrayerIntent

These should be reusable from widgets, Shortcuts, Spotlight, Siri suggestions, and future Control Center controls.

D. Local Notifications
Use local notifications for:
- Saf opens before prayer
- prayer time starts
- Small Saf members getting ready
- Fajr wake-up reminder

Notification examples:
- “Fajr Saf opens in 10 minutes.”
- “Your Saf is waking up.”
- “126 people are preparing for Asr.”
- “When it’s time, stand together.”
- “Your Small Saf is getting ready.”

Never use guilt-based notification copy.

E. Optional future native surfaces
Prepare architecture for:
- Apple Watch companion app
- Control Center control on iOS 18+
- StandBy display
- Siri phrase: “Join my Saf”
- Shortcuts automation

Do not fully implement Apple Watch or Control Center in MVP unless straightforward.
But structure App Intents so these surfaces can be added later.

--------------------------------------------
3. ONBOARDING
--------------------------------------------

Build onboarding in SwiftUI.

Screen 1:
Title:
“Start salah with others.”
Subtitle:
“Join a live silent Saf when prayer time approaches.”

Screen 2:
Title:
“See Muslims getting ready.”
Subtitle:
“Getting up. Making wudu. Ready. Praying.”

Screen 3:
Title:
“No chat. No camera. No pressure.”
Subtitle:
“Just presence at the moment of starting salah.”

Screen 4:
Location permission:
Title:
“Set your prayer times.”
Options:
- Use current location
- Choose city manually

If user allows location:
- Request CoreLocation permission
- Store approximate location preference
- Do not show exact location publicly

If user denies location:
- Show manual city search input
- Allow default city selection

Screen 5:
Calculation method:
Allow user to choose:
- Muslim World League
- Egyptian
- Karachi
- Umm al-Qura
- ISNA
- Turkey / Diyanet if supported
- Custom later

Screen 6:
Display mode:
- Anonymous
- First name

Screen 7:
Notification preference:
- 20 minutes before Fajr
- 10 minutes before each prayer
- 5 minutes before each prayer
- At prayer time
- Small Saf nudges
- Disable all

Keep onboarding short and beautiful.

--------------------------------------------
4. TAB STRUCTURE
--------------------------------------------

Use TabView with 4 tabs:

1. Home
2. Safs
3. Insights
4. Profile

--------------------------------------------
5. HOME SCREEN
--------------------------------------------

Home should focus on the next prayer.

Example layout:

Top:
Vakt logo / wordmark
small city name
settings icon

Main card:
Next prayer
Dhuhr
Starts in 08:42

Live Saf:
126 people are getting ready

Main CTA:
Join Saf

Secondary CTA:
View all prayers

Below:
Today’s prayers as compact cards:

Fajr
05:14
Completed / Closed

Dhuhr
13:08
Opens in 08:42

Asr
17:02
Upcoming

Maghrib
20:41
Upcoming

Isha
22:19
Upcoming

Each card should show:
- prayer name
- time
- lobby status
- live count if active
- join button if open

Home screen states:
- No location: prompt to set location
- No active Saf: show when next Saf opens
- Loading prayer times: show skeleton cards
- Offline: show cached prayer times and offline banner

--------------------------------------------
6. PRAYER LOBBY SCREEN
--------------------------------------------

When user taps Join Saf, open PrayerLobbyView.

Header:
Dhuhr Saf
Starts in 04:31

Live count:
126 people here

Status groups:
Getting up: 31
Making wudu: 18
Finding a place: 9
Ready: 42
Praying: 26

Represent participants as:
- small glowing dots
- initials if user opted into first name
- grouped by status

Avoid social-network feel.

Main status buttons:
- I’m getting up
- Making wudu
- Finding a place
- I’m ready

At prayer time, show primary CTA:
Start Salah

When user taps Start Salah:
- Update status to praying
- Create prayer log with started_at
- Start quiet mode screen
- Optionally start/update Live Activity
- Dim interface
- Show:
  “You’ve joined the Saf. Put your phone away.”
- Start silent 7-minute timer

Quiet mode:
- no animations except subtle breathing/pulse
- no participant list
- no social feed
- no content
- small hidden “End early” link

After timer:
Ask:
“Did you start salah?”

Options:
- Yes, on time
- I started late
- Not this time

Copy:
“Let’s protect the next prayer.”

Do not say:
“You failed.”
“You missed again.”
“Your streak is broken.”

--------------------------------------------
7. ALL SAFS SCREEN
--------------------------------------------

Show all five prayer lobbies.

Each lobby card:
- prayer name
- prayer time
- lobby open/closed/upcoming
- opens in X
- closes in X
- live count
- join button if open

Lobby windows should be configurable constants:

Fajr:
opens 20 minutes before prayer
closes 45 minutes after prayer

Dhuhr:
opens 15 minutes before prayer
closes 35 minutes after prayer

Asr:
opens 15 minutes before prayer
closes 35 minutes after prayer

Maghrib:
opens 10 minutes before prayer
closes 25 minutes after prayer

Isha:
opens 15 minutes before prayer
closes 45 minutes after prayer

Also show Small Saf section:
- My Small Safs
- Create Small Saf
- Join with invite code

--------------------------------------------
8. SMALL SAF FEATURE
--------------------------------------------

Small Saf = private 3–7 person prayer-start group.

Flow:
Create Small Saf:
- Group name
- Prayer coverage:
  - All prayers
  - Fajr only
  - Custom
- Privacy:
  - Anonymous statuses only
  - Show first names
- Generate invite code/link

Small Saf room:
- group name
- next prayer
- members
- current statuses
- live preparation count
- gentle nudge button

Nudge:
“Your Saf is getting ready for Fajr.”

Rules:
- No chat
- No comments
- No history unless user chooses to share
- No leaderboards
- No “who missed” shame screen

Member statuses:
- Not joined yet
- Getting up
- Making wudu
- Ready
- Praying

Allow user to leave Small Saf.

--------------------------------------------
9. INSIGHTS SCREEN
--------------------------------------------

Do not create streaks as the main mechanic.

Create “Start Insights”.

Weekly insights:
- Started within first 15 minutes: X prayers
- Started within first 30 minutes: Y prayers
- Most consistent prayer
- Most delayed prayer
- Best day
- Small Saf helped you start X prayers earlier
- Average start delay by prayer

Use calm visualizations:
- soft bars
- circular rhythm
- no red failure UI

Good copy:
“Your prayer starts this week”
“Most protected prayer: Fajr”
“Most delayed prayer: Asr”
“Small Saf helped you start earlier 4 times”
“Let’s protect the next prayer.”

Bad copy:
“You failed”
“You broke your streak”
“You missed again”
“Bad performance”

--------------------------------------------
10. PROFILE / SETTINGS
--------------------------------------------

Profile sections:

Account:
- display name
- anonymous mode
- sign out

Prayer settings:
- city
- location permission state
- calculation method
- madhab/asr method if relevant
- time format
- timezone display

Notifications:
- per-prayer notification settings
- Small Saf nudges
- Live Activity preferences

Privacy:
- anonymous by default
- hide exact location
- hide individual history
- delete account
- export my data

About:
- product positioning
- no chat / no camera / no proof
- privacy statement

--------------------------------------------
11. PRAYER TIME SERVICE
--------------------------------------------

Create a clean PrayerTimeService abstraction.

Protocol:
PrayerTimeProviding

Functions:
- getPrayerTimes(for date: Date, location: Coordinate, method: CalculationMethod) async throws -> DailyPrayerTimes
- getCurrentPrayerWindow(now: Date, prayerTimes: DailyPrayerTimes) -> PrayerWindow?
- getNextPrayer(now: Date, prayerTimes: DailyPrayerTimes) -> PrayerTime

Use a reliable prayer calculation approach.

For MVP:
- Implement real calculation if a strong Swift-compatible library is available
- Otherwise create a clean placeholder provider with Istanbul default times for development
- Keep implementation replaceable

Important:
- handle timezone correctly
- recalculate daily
- cache today and tomorrow
- support manual city fallback
- use approximate location where possible

Models:
PrayerName:
- fajr
- dhuhr
- asr
- maghrib
- isha

DailyPrayerTimes:
- date
- city
- timezone
- fajr
- dhuhr
- asr
- maghrib
- isha

PrayerWindow:
- prayerName
- opensAt
- prayerTime
- closesAt
- status: upcoming / open / closed

--------------------------------------------
12. SUPABASE INTEGRATION
--------------------------------------------

Use Supabase Swift SDK.

Create:
SupabaseManager
AuthService
ProfileService
PrayerSessionService
PresenceService
SmallSafService
PrayerLogService

Use async/await.

Authentication:
- Email magic link or email/password for MVP
- Apple Sign In optional but preferred for native iOS polish
- Store session securely

Realtime:
Use Supabase Realtime channels for:
- global prayer session presence
- Small Saf presence

For MVP:
- update presence rows on status changes
- subscribe to presence/session changes
- aggregate counts client-side
- expire presence after inactivity

Presence expiry:
If user has not updated for more than 15 minutes, treat as inactive.

--------------------------------------------
13. SUPABASE SQL SCHEMA
--------------------------------------------

Create migration files.

profiles:
- id uuid primary key references auth.users
- display_name text
- anonymous_name text
- city text
- country text
- latitude numeric
- longitude numeric
- calculation_method text
- notification_preferences jsonb
- privacy_preferences jsonb
- created_at timestamptz default now()
- updated_at timestamptz default now()

prayer_sessions:
- id uuid primary key default gen_random_uuid()
- prayer_name text not null
- prayer_date date not null
- city text
- country text
- timezone text
- opens_at timestamptz not null
- prayer_time timestamptz not null
- closes_at timestamptz not null
- created_at timestamptz default now()

session_presence:
- id uuid primary key default gen_random_uuid()
- session_id uuid references prayer_sessions(id) on delete cascade
- user_id uuid references profiles(id) on delete cascade
- status text not null
- is_anonymous boolean default true
- joined_at timestamptz default now()
- updated_at timestamptz default now()

prayer_logs:
- id uuid primary key default gen_random_uuid()
- user_id uuid references profiles(id) on delete cascade
- prayer_name text not null
- prayer_date date not null
- prayer_time timestamptz
- started_status text
- started_at timestamptz
- start_bucket text
- created_at timestamptz default now()

small_safs:
- id uuid primary key default gen_random_uuid()
- name text not null
- owner_id uuid references profiles(id) on delete cascade
- prayer_scope jsonb
- invite_code text unique not null
- created_at timestamptz default now()

small_saf_members:
- id uuid primary key default gen_random_uuid()
- small_saf_id uuid references small_safs(id) on delete cascade
- user_id uuid references profiles(id) on delete cascade
- role text default 'member'
- joined_at timestamptz default now()

small_saf_presence:
- id uuid primary key default gen_random_uuid()
- small_saf_id uuid references small_safs(id) on delete cascade
- user_id uuid references profiles(id) on delete cascade
- prayer_name text not null
- prayer_date date not null
- status text not null
- updated_at timestamptz default now()

Add constraints:
- prayer_name must be one of fajr, dhuhr, asr, maghrib, isha
- status must be one of getting_up, making_wudu, finding_place, ready, praying
- start_bucket must be one of first_15, first_30, late, not_this_time

Add indexes:
- prayer_sessions(prayer_date, prayer_name, city)
- session_presence(session_id)
- session_presence(user_id)
- prayer_logs(user_id, prayer_date)
- small_saf_members(user_id)
- small_saf_presence(small_saf_id, prayer_date, prayer_name)

Row Level Security:
- users can read their own profile
- users can update their own profile
- users can read global anonymous aggregated session presence
- users can insert/update/delete only their own session_presence
- users can insert/read/update only their own prayer_logs
- users can read Small Saf data only if they are members
- owners can manage their Small Saf
- members can update only their own small_saf_presence

Create helper RPCs if needed:
- get_session_presence_counts(session_id)
- get_small_saf_presence(small_saf_id, prayer_name, prayer_date)
- join_small_saf(invite_code)

--------------------------------------------
14. SWIFT DATA MODELS
--------------------------------------------

Create strong Swift types.

enum PrayerName: String, Codable, CaseIterable, Identifiable {
  case fajr
  case dhuhr
  case asr
  case maghrib
  case isha
}

enum PresenceStatus: String, Codable, CaseIterable, Identifiable {
  case gettingUp = "getting_up"
  case makingWudu = "making_wudu"
  case findingPlace = "finding_place"
  case ready
  case praying
}

enum StartBucket: String, Codable {
  case first15 = "first_15"
  case first30 = "first_30"
  case late
  case notThisTime = "not_this_time"
}

struct DailyPrayerTimes
struct PrayerTime
struct PrayerWindow
struct PrayerSession
struct PresenceSummary
struct SmallSaf
struct SmallSafMember
struct PrayerLog
struct WeeklyInsights
struct UserProfile

Use Codable, Identifiable, Hashable where appropriate.

--------------------------------------------
15. FEATURE ARCHITECTURE
--------------------------------------------

Suggested folder structure:

Vakt/
  App/
    VaktApp.swift
    AppRouter.swift
    AppState.swift

  Core/
    Supabase/
      SupabaseManager.swift
    Location/
      LocationManager.swift
    Notifications/
      NotificationManager.swift
    LiveActivities/
      SafLiveActivityManager.swift
    WidgetsShared/
      SharedModels.swift
    DesignSystem/
      Colors.swift
      Typography.swift
      Components.swift

  Features/
    Auth/
      AuthView.swift
      AuthViewModel.swift
      AuthService.swift

    Onboarding/
      OnboardingView.swift
      OnboardingViewModel.swift

    Home/
      HomeView.swift
      HomeViewModel.swift
      PrayerCardView.swift

    Safs/
      SafsView.swift
      PrayerLobbyView.swift
      PrayerLobbyViewModel.swift
      QuietSalahView.swift

    SmallSaf/
      SmallSafListView.swift
      CreateSmallSafView.swift
      JoinSmallSafView.swift
      SmallSafRoomView.swift
      SmallSafViewModel.swift

    Insights/
      InsightsView.swift
      InsightsViewModel.swift

    Profile/
      ProfileView.swift
      ProfileViewModel.swift

  Services/
    PrayerTimeService.swift
    PrayerSessionService.swift
    PresenceService.swift
    SmallSafService.swift
    PrayerLogService.swift
    ProfileService.swift

  Resources/
    Assets.xcassets

VaktWidgets/
  NextPrayerWidget.swift
  TodayPrayersWidget.swift
  LockScreenPrayerWidget.swift
  VaktWidgetBundle.swift

VaktLiveActivity/
  SafLiveActivity.swift
  SafActivityAttributes.swift

VaktIntents/
  JoinCurrentSafIntent.swift
  SetPrayerStatusIntent.swift
  StartSalahIntent.swift
  OpenNextPrayerIntent.swift

Supabase/
  migrations/
    001_initial_schema.sql
    002_rls_policies.sql
    003_rpc_helpers.sql

--------------------------------------------
16. DESIGN SYSTEM
--------------------------------------------

Visual direction:
- deep charcoal / near-black background
- warm off-white text
- muted gold accent
- soft green only as minor secondary accent
- rounded cards
- subtle gradients
- glowing dots for live presence
- no excessive mosque icons
- no cliché Islamic clipart
- no gamified badges
- no aggressive red states

SwiftUI components:
- VaktCard
- PrayerCountdownView
- LiveCountView
- StatusChip
- PresenceDotsView
- PrayerRowCard
- PrimaryButton
- SecondaryButton
- EmptyStateView
- GentleBanner
- SafTimerView

Animation:
- subtle dot pulsing
- smooth countdown transitions
- soft fade between statuses
- no confetti
- no reward animation

Haptics:
Use light haptic feedback when:
- joining Saf
- changing status
- pressing Start Salah

Do not overuse haptics.

--------------------------------------------
17. COPYWRITING RULES
--------------------------------------------

Use short, gentle, direct copy.

Good:
- “Stand together.”
- “Your Saf is getting ready.”
- “Protect the next prayer.”
- “You are not alone.”
- “Start with the Saf.”
- “Put your phone away.”
- “Let’s protect the next prayer.”
- “When it’s time, stand together.”

Bad:
- “You failed.”
- “You missed again.”
- “Your streak is broken.”
- “Don’t be lazy.”
- “Allah is watching you.”
- “Everyone prayed except you.”

Keep language calm and respectful.

--------------------------------------------
18. LOCAL NOTIFICATION LOGIC
--------------------------------------------

Implement NotificationManager.

Schedule notifications daily after calculating prayer times.

Notification types:
- safOpening
- prayerTime
- smallSafNudge
- fajrWake

User preferences:
- global enabled/disabled
- per prayer enabled/disabled
- minutes before prayer
- Small Saf social nudges enabled/disabled

Examples:
Fajr:
“Your Fajr Saf is waking up.”

Dhuhr:
“Dhuhr Saf opens in 10 minutes.”

Asr:
“126 people are preparing for Asr.”

Maghrib:
“When it’s time, stand together.”

Isha:
“Your Saf is getting ready.”

--------------------------------------------
19. LIVE ACTIVITY LOGIC
--------------------------------------------

Create ActivityKit models.

SafActivityAttributes:
- prayerName
- prayerTime
- opensAt
- closesAt
- city

ContentState:
- liveCount
- userStatus
- timeRemaining
- lobbyState
- updatedAt

Start Live Activity when:
- user joins Saf
- or user enables auto Live Activity for next prayer

Update Live Activity when:
- status changes
- prayer time approaches
- live count changes when app is active
- local countdown changes where possible

End Live Activity when:
- lobby closes
- user completes quiet salah timer
- user manually ends

Do not rely on perfect background realtime updates for MVP.
Live Activity should still be useful with local countdown and last known live count.

--------------------------------------------
20. WIDGET LOGIC
--------------------------------------------

Use WidgetKit.

Widgets should read cached data from App Group shared storage.

Create App Group:
group.com.yourcompany.vakt

Shared cache:
- next prayer
- today’s prayer times
- next Saf window
- last known live count
- user city

Widgets:
1. SmallNextPrayerWidget
2. MediumTodayPrayerWidget
3. LockScreenCountdownWidget

Deep links:
vakt://saf/current
vakt://saf/fajr
vakt://saf/dhuhr
vakt://saf/asr
vakt://saf/maghrib
vakt://saf/isha
vakt://smallsaf/{id}

--------------------------------------------
21. APP INTENTS
--------------------------------------------

Create App Intents:

JoinCurrentSafIntent:
- Finds current or next open Saf
- Opens app or performs join if possible
- Updates presence to getting_up

SetPrayerStatusIntent:
Parameters:
- prayerName
- status

StartSalahIntent:
- Updates presence to praying
- Creates/updates prayer log
- Opens QuietSalahView or starts Live Activity update

OpenNextPrayerIntent:
- Deep links to next prayer lobby

Make intents safe:
- If no active Saf exists, return clear message:
  “The next Saf opens before Asr.”

--------------------------------------------
22. OFFLINE / CACHING
--------------------------------------------

The app should work gracefully offline.

Offline behavior:
- show cached prayer times
- allow user to start local quiet timer
- queue prayer log locally
- sync when online
- show “Offline — using cached times” banner

Use local persistence for:
- onboarding completed
- user preferences
- cached prayer times
- cached city
- unsynced prayer logs
- last known active Saf data

--------------------------------------------
23. PRIVACY REQUIREMENTS
--------------------------------------------

Privacy-first by default.

Rules:
- exact location is never shown to other users
- user can be anonymous
- no public prayer history
- no proof of prayer
- no camera
- no microphone
- no contact upload
- no public profile
- no follower graph
- no guilt notifications
- no public missed-prayer indicators

Small Saf privacy:
- group members only see current status during active prayer windows
- do not show detailed long-term history unless user explicitly opts in
- no “missed” labels next to names

Add clear privacy copy:
“Vakt helps you start salah. It does not prove your salah.”

--------------------------------------------
24. EMPTY STATES
--------------------------------------------

No active Saf:
“The next Saf opens before Asr.”

No users:
“You’re the first one here. Others may join soon.”

No location:
“Set your city to calculate prayer times.”

No Small Saf:
“Create a Small Saf with friends or family.”

No insights:
“Start a few prayers with Vakt to see your weekly rhythm.”

Offline:
“You’re offline. Showing cached prayer times.”

--------------------------------------------
25. MVP SUCCESS CRITERIA
--------------------------------------------

The user should be able to:

- install and launch the native iOS app
- sign up or sign in
- complete onboarding
- allow location or choose city manually
- select prayer calculation method
- see today’s five prayer times
- see next prayer countdown
- receive local notification when a Saf opens
- join an active Saf
- update preparation status
- see realtime aggregated counts from other users
- press Start Salah
- enter quiet salah mode
- complete the silent timer
- log whether they started on time
- create a Small Saf
- invite/join a Small Saf with code
- see Small Saf member statuses during active prayer windows
- see weekly start insights
- see a Home Screen widget
- start or view a Live Activity for active Saf
- use deep links from notifications/widgets

--------------------------------------------
26. IMPLEMENTATION ORDER
--------------------------------------------

Build in this order:

1. Project setup
- SwiftUI app
- Supabase config
- environment config
- design system

2. Auth
- sign in / sign up
- session handling
- profile creation

3. Prayer time foundation
- manual city fallback
- default Istanbul dev data
- PrayerTimeService abstraction
- current prayer window logic

4. Home screen
- next prayer
- today prayer cards
- join Saf CTA

5. Prayer lobby
- status buttons
- presence summary
- local mock presence first

6. Supabase presence
- session presence table
- realtime updates
- client-side aggregation

7. Quiet salah mode
- Start Salah
- 7-minute timer
- prayer log

8. All Safs screen

9. Small Saf
- create
- invite code
- join
- status presence

10. Insights
- weekly start metrics

11. Notifications
- local notifications based on prayer times

12. Widgets
- next prayer widget
- today prayers widget

13. Live Activities
- active Saf Live Activity
- Lock Screen / Dynamic Island UI

14. Polish
- animations
- haptics
- empty states
- offline cache
- README

--------------------------------------------
27. DELIVERABLES
--------------------------------------------

Create a complete native iOS MVP with:

- Xcode project
- SwiftUI app target
- Widget extension
- Live Activity support
- App Intents
- Supabase integration
- SQL migration files
- local notification setup
- CoreLocation location permission flow
- manual city fallback
- clean feature-based architecture
- README

README should include:
- Xcode version assumptions
- iOS target
- how to configure Supabase URL and anon key
- how to apply SQL migrations
- how to run locally
- how to test notifications
- how to test widgets
- how to test Live Activities
- known limitations
- next features

--------------------------------------------
28. KNOWN MVP LIMITATIONS TO DOCUMENT
--------------------------------------------

Document these honestly:

- prayer time calculation may start with limited method support
- Live Activity realtime counts may use last known count unless push updates are added
- Apple Watch is not included in MVP
- Control Center controls are future work
- city search may be basic in MVP
- no guarantee of exact prayer time correctness until calculation provider is finalized

--------------------------------------------
29. FINAL PRODUCT GUARDRAILS
--------------------------------------------

Never turn this into a generic Islamic super app.

Keep the product centered on one behavior:

The moment before salah.

The app should answer one question:

“Who else is standing now?”

Build the MVP around that.