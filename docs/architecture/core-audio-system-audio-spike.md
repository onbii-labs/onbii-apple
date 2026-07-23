# Core Audio System-Audio Spike

Status: Core API feasibility validated; dual-source prototype implemented,
device validation pending

Date: 2026-07-23

## Question

Can a sandboxed macOS 14.2+ Onbii app, after an explicit user action, receive
audible system output through a Core Audio process tap?

This is the first feasibility question. It does not establish that every meeting
application can be captured reliably or that Onbii should promise system-audio
recording.

## Corrected API Direction

The first spike used ScreenCaptureKit's system content-sharing picker. Although
ScreenCaptureKit can return audio alongside a selected display or application,
that presents a screen-sharing model to someone who asked to capture audio.
Onbii does not use that interaction for its system-audio recorder.

Apple provides Core Audio process taps specifically to capture outgoing audio
from a process or group of processes. The corrected probe uses a private,
unmuted stereo global tap and a private HAL aggregate device. It does not request
or receive screen content.

In Core Audio terminology, "outgoing audio from a process" is audio the
application sends to the Mac's output device. During a Zoom, Teams, or Nextcloud
Talk call, this is normally the remote participants heard through the user's
speakers or headphones. It is not the local microphone signal sent into the
meeting application.

## Complete Call-Capture Boundary

A useful call recording needs both legs:

```text
remote participants -> meeting app output -> Core Audio process tap
local participant   -> microphone input   -> microphone capture
```

The process tap validates the remote/application-output leg. The existing
microphone recorder validates the local leg independently. The development app
now starts both in one explicit session and preserves the two resulting source
tracks with their individual start times and durations. That combined path has
not yet been validated on-device or for aligned long-session timing.

The first real call-capture path should acquire both concurrently and preserve
them as distinct source tracks. A convenience mix may be added as a derived
resource with provenance; it should not replace the original tracks.

## Probe And Recorder

The macOS development app exposes a clearly labelled
**Probe Application Audio** control. It:

1. creates a private global Core Audio process tap;
2. leaves application audio audible through the normal output device;
3. attaches the tap to a private aggregate audio device;
4. starts audio I/O after the user's explicit button press;
5. reports only after a non-silent floating-point audio sample arrives; and
6. discards every sample without writing a recording.

The app includes `NSAudioCaptureUsageDescription`. The first start should produce
macOS's system-audio recording permission prompt.

After the global probe passed, a short application-isolation experiment exposed
the policy and usability cost of mapping audible streams to helper processes.
Finder Preview audio, for example, is produced by `QuickLookUIService`, not
Finder or a user-facing Preview selection. That filtering work is deliberately
deferred.

**Start Call Capture** therefore records the global stereo system-output mix to
CAF and the current default microphone to M4A concurrently. Staging files are
deleted only after both have been preserved inside a completed `.onbii`
package.

This follows Apple's
[`Capturing system audio with Core Audio taps`](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)
sample and requires macOS 14.2 or later.

## Success Criteria

The narrow API feasibility question is answered positively when:

- macOS presents system-audio recording permission rather than screen sharing;
- ordinary audio from a browser or media application produces the
  **Audible application output is reaching the Core Audio tap** state;
- stopping tears down the I/O procedure, private aggregate device, and tap;
- the source application remains audible while probing; and
- denial and Core Audio failures appear as explicit UI states.

Before making a meeting-capture promise, repeat the test with the meeting
applications Onbii intends to support and with common output routes such as
built-in speakers, wired audio, and Bluetooth.

## Validation Result

On 2026-07-23, the development app passed the initial device test:

- macOS presented the system-audio recording permission;
- audio playing in another application produced the
  **Audible application output is reaching the Core Audio tap** state;
- stopping the probe completed cleanly; and
- the source application remained audible throughout.

This validates the Core Audio process-tap mechanism for the global
application-output mix on the tested Mac. It does not yet validate
application-specific isolation, simultaneous microphone capture, timing
alignment, long sessions, alternate output routes, or individual meeting
applications.

The next validation pass should confirm:

- sounds from multiple applications enter the system-audio source;
- system output remains audible during capture;
- the default microphone enters the microphone source;
- both source files survive in one package; and
- stopping tears down both recorders and permits a second capture.

## Non-Goals

This spike does not:

- preserve or encode system audio;
- combine system audio with microphone input;
- create an `.onbii` object;
- select or isolate one application;
- detect meetings or start recording automatically;
- validate echo, drift, channel layout, long-session stability, or sleep/wake;
- prove capture behavior for a specific meeting application; or
- alter the explicit-consent rule.

## Decision Gate

After device validation, record one of these outcomes here:

- proceed with an explicit Core Audio system-audio recorder in `OnbiiCapture`;
- narrow support to verified applications or output routes;
- keep microphone capture and file import as the Milestone 1 macOS promise while
  deferring system audio.

Only the first two outcomes should lead to an audio writer and bundle-pipeline
integration. That integration must then validate simultaneous microphone
capture before it is described as call recording.

Outcome: proceed with a bounded global-system-output and default-microphone
capture prototype. Retain them as separate source tracks. Defer per-application
filtering and application-triggered capture until a later feature, and do not
describe the result as supported meeting capture until the remaining validation
matrix passes.
