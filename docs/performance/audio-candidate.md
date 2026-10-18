# Alarm audio candidate: lower-rate IMA4 CAF

Audio lane, 2026-10-18. Baseline: `abd7312` / unchanged production assets from `c42b88e`. Only the generator and eight CAF resources change app inputs. No runtime, UI, sound identity, selection, filename, melody, note timing, voice partial, envelope, gain, reverb or normalization changes.

## Result and selection

Audio resource inputs: **5,280,736 → 2,445,686 bytes**, saving **2,835,050 bytes (53.6866%)**. Meets the 2,587,560.64-byte v1 component ceiling by 141,874.64 bytes. Does not meet the 2,112,294.4-byte stretch ceiling. These are logical source resource bytes; app bundle, ZIP proxy, installed/thinned size, memory and speed are separate measurements.

Synthesize the identical deterministic 44,100 Hz mono signal first, then use Apple afconvert with `-f caff -d ima4@<rate> -r 127 --src-complexity bats --no-filler`. Keep six bright voices at 22,050 Hz; use 16,000 Hz for Beacon and Morning Piano only. Their explicit highest oscillator partials are 2,349.32 Hz and 4,703.94 Hz respectively, comfortably below 8 kHz. This avoids changing reverb randomness or aliasing upper partials by synthesizing directly at the output rate.

Padding removal alone saves only 31,136 bytes across the old CAFs. Uniform 22,050 Hz at the observed candidate container layout would total about 2,625,616 bytes (50.2794% smaller), exceeding the owner’s >50% request but missing the stricter v1 51% ceiling. The mixed rate candidate passes that ceiling while retaining more bandwidth than uniform 16 kHz. Uniform 16 kHz was not generated or auditioned; it is not accepted because bright voices would lose additional upper partials. The accepted candidate already satisfies this lane’s required target.

## Compatibility evidence

Research checked 2026-10-18, using Apple sources:

- [Current UNNotificationSound: Prepare Sound Resources](https://developer.apple.com/documentation/usernotifications/unnotificationsound#Prepare-Sound-Resources) documents IMA/ADPCM inside CAF and custom sounds shorter than 30 seconds, and demonstrates `afconvert -d ima4 -f caff`. Current documentation JSON was retrieved as well as the rendered page.
- [Current ActivityKit AlertSound.named(_:)](https://developer.apple.com/documentation/activitykit/alertconfiguration/alertsound/named(_:)) specifies the app main bundle or app container Library/Sounds lookup. [Apple WWDC25 AlarmKit session](https://developer.apple.com/videos/play/wwdc2025/230/) connects AlarmKit custom audio to ActivityKit AlertSound.
- [Apple CAF specification](https://developer.apple.com/library/archive/documentation/MusicAudio/Reference/CAFSpec/CAF_spec/CAF_spec.html) defines the free chunk as optional padding. Native `afconvert -h` exposes `--no-filler`, so no hand-edited container is needed.
- [Apple audio guidance](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/MultimediaPG/UsingAudio/UsingAudio.html) supports IMA4 software decoding and reducing sample rate for smaller sound resources. It does not provide a specific AlarmKit sample-rate whitelist.

Compatibility conclusion: this preserves the documented custom-alert codec/container family and duration constraint, with standard lower audio sample rates that the installed Apple Core Audio encoder/decoder accepts. The format guidance is explicit for notification/system alert sounds; applying it to AlarmKit’s ActivityKit custom sounds is an informed compatibility inference, not an explicit Apple guarantee for these exact rates. Neither the current ActivityKit API reference nor the AlarmKit session enumerates rate-specific restrictions. No AAC/MP3/ALAC substitution is used. Actual phone AlarmKit scheduling, locked-screen playback, looping, Silent/Focus behavior and subjective sound identity remain unverified. No phone was operated and no simulator or Xcode build was run.

## Container and signal measurements

All originals are mono IMA4, 44,100 Hz, 1,234,800 valid frames, exactly 28 seconds and 660,092 bytes each. All candidates remain mono IMA4 and exactly 28 seconds. Original free payload is 3,880 bytes/file; candidates have no free chunk. Fixed packets are 34 bytes / 64 frames. Candidate 22,050 Hz files have 9,647 packets, 8 remainder frames; 16,000 Hz files have 7,001 packets, 64 remainder frames. Remainders are codec padding outside valid duration; native decoding returns exactly the valid frames. Core Audio writes zero in the fixed-rate packet table packet-count field, so tests derive actual packet count from the data chunk and verify the frame equation.

| Tone / unchanged file stem | Output Hz | Valid frames | After bytes | Saved bytes |
| --- | ---: | ---: | ---: | ---: |
| Beacon | 16000 | 448,000 | 238,237 | 421,855 |
| Chimes | 22050 | 617,400 | 328,202 | 331,890 |
| Crystal | 22050 | 617,400 | 328,202 | 331,890 |
| Daybreak | 22050 | 617,400 | 328,202 | 331,890 |
| Glass | 22050 | 617,400 | 328,202 | 331,890 |
| Marimba | 22050 | 617,400 | 328,202 | 331,890 |
| MorningPiano | 16000 | 448,000 | 238,237 | 421,855 |
| Ripple | 22050 | 617,400 | 328,202 | 331,890 |

Native decoded I16 samples normalized by 32768; peak and RMS are linear full-scale amplitudes. No level fitting, clipping or post-encoding normalization is applied. RMS delta uses before/after decoded signals converted to a common 44,100 Hz with the same Apple bats/127 SRC. The common-rate comparison preserves the original 28-second timeline, without phase alignment.

| Tone | Peak before → after (native) | RMS before → after (native) | Common-rate RMS Δ dB | Wave correlation | Envelope max Δ dB |
| --- | ---: | ---: | ---: | ---: | ---: |
| Beacon | 0.86191 → 0.90427 | 0.28109 → 0.28137 | +0.0085 | 0.999181 | 0.074 |
| Chimes | 0.85248 → 0.86615 | 0.17442 → 0.17448 | +0.0032 | 0.999649 | 0.019 |
| Crystal | 0.85483 → 0.84540 | 0.15577 → 0.15589 | +0.0064 | 0.998239 | 0.046 |
| Daybreak | 0.85513 → 0.84686 | 0.12962 → 0.12963 | +0.0007 | 0.998715 | 0.041 |
| Glass | 0.85544 → 0.85223 | 0.17479 → 0.17508 | +0.0140 | 0.998795 | 0.049 |
| Marimba | 0.85892 → 0.86697 | 0.17226 → 0.17233 | +0.0035 | 0.999347 | 0.022 |
| MorningPiano | 0.86154 → 0.89017 | 0.16352 → 0.16412 | +0.0315 | 0.997323 | 0.093 |
| Ripple | 0.84647 → 0.82309 | 0.16716 → 0.16721 | +0.0023 | 0.999703 | 0.018 |

Envelope comparison uses 280 consecutive 100 ms RMS windows and includes windows above 1% of the original maximum RMS. Envelope correlation is at least 0.99999069; maximum active-window level deviation is 0.093 dB. Whole-signal RMS changes by at most 0.0315 dB. Largest native peak increase is Beacon, 0.86191 → 0.90427 (still below full scale). Lower-rate IMA4 changes quantization noise and transient peaks; perceptual equivalence is not asserted.

Spectral comparison: unwindowed whole-signal rFFT band power, each row normalized to its own total power. Entries are percent before → after at common 44,100 Hz. High-band energy in the old decoded IMA4 includes codec noise, so a separate measurement uses the unchanged uncompressed synthesized signal to bound musical energy above the new Nyquist frequency.

| Tone | 0–4 kHz % | 4–8 kHz % | 8–11.025 kHz % | >11.025 kHz % | Source energy above new Nyquist % |
| --- | ---: | ---: | ---: | ---: | ---: |
| Beacon | 99.98681 → 99.92892 | 0.00309 → 0.07108 | 0.00228 → 0.00000 | 0.00781 → 0.00000 | 0.000000 |
| Chimes | 99.97533 → 99.94840 | 0.01701 → 0.03660 | 0.00166 → 0.01500 | 0.00600 → 0.00000 | 0.000000 |
| Crystal | 99.41974 → 99.29946 | 0.55385 → 0.63318 | 0.00602 → 0.06737 | 0.02039 → 0.00000 | 0.000000 |
| Daybreak | 98.97510 → 98.95336 | 0.92705 → 0.96017 | 0.05077 → 0.08646 | 0.04708 → 0.00000 | 0.027850 |
| Glass | 99.81162 → 99.71584 | 0.17017 → 0.23819 | 0.00408 → 0.04597 | 0.01413 → 0.00000 | 0.000000 |
| Marimba | 99.17801 → 99.14929 | 0.77419 → 0.80033 | 0.02824 → 0.05038 | 0.01956 → 0.00000 | 0.008760 |
| MorningPiano | 99.98665 → 99.84970 | 0.00639 → 0.15030 | 0.00153 → 0.00000 | 0.00543 → 0.00000 | 0.000000 |
| Ripple | 99.75633 → 99.73793 | 0.23024 → 0.24466 | 0.00683 → 0.01741 | 0.00660 → 0.00000 | 0.001335 |

Anti-alias resampling necessarily discards content above output Nyquist and can attenuate the transition band below it. Measured source energy above new Nyquist is at most 0.027850% (Daybreak). This energy fraction and waveform/envelope correlations support retaining recognizable identity but do not replace listening or phone acceptance. Six 22.05 kHz choices retain bandwidth through most of the audible treble; the two lower-rate choices retain their intended oscillator bands.

## Verification and retained evidence

- `python3 ios/Tools/make_alarm_sounds.py` generated the resources; a second generation using `--output-dir` produced byte-identical SHA-256 hashes for all eight on this host (Python 3.9 / NumPy 1.26.4, macOS Core Audio). Cross-version encoder/NumPy bit identity is not claimed.
- `python3 -m unittest discover -s tests/performance -p test_audio_resources.py -v`: 3 tests passed in 0.452 s. Covers the eight choices, IMA4/mono/rate/frame contract, packet/padding consistency, component size ceiling, distinct payloads and native Core Audio decode without clipped samples. The decoder test skips outside macOS; container tests use only the standard library.
- Initial test harness failures were CAF fixed-packet-count and Python 3.9 WAV_EXTENSIBLE parsing assumptions. Corrected by deriving packets from the actual payload and decoding to PCM CAF. No product assertion was removed and no audio changed to satisfy the harness.

Canonical primary evidence directory: `/Users/yuanlu/code/one-app/tests/results/runs/performance-climb-20261018/audio/`.

It retains `original/*.caf` and the original generator, `candidate/*.caf`, `repeat/*.caf`, all decoded PCM comparisons, `comparison.json` (full numeric measurements, metadata and hashes), `analyze.py` (rerunnable with the candidate checkout path), `analysis.log`, `regeneration.log`, `tests.log`, `afconvert-help.txt`, and downloaded official sources with URL manifest. These generated outputs stay outside Git. `tests/qa/journal.py` indexes the evidence paths, sizes and SHA-256 in the primary checkout’s QA Activity SQLite journal under session `performance-climb-20261018-audio`. Required test inputs are the versioned CAF assets, not temporary files.

No Swift tests, builds, simulator journeys, performance benchmarks or physical-device checks were run in this lane. Package integration and real AlarmKit playback must be reported separately by the owning integration lane.
