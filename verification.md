# Shell shadow verification

Implementation: `f3208bac`, acceptance capture settling: `6fa78892`, offscreen test stabilization: `418e6e0c`.

Base: `28ceaae70ebac3a0edcc21f2faa77a90dc6d404c` (`quattro`).

## Functional coverage

The previously outstanding UI checks passed in the existing disposable VM at 1896×1030 / 1× and verified 1920×1080 / 1.25×. Forty assertions covered:

- **MultiSelect:** search, keyboard selection and deselection, pointer selection, Escape, clicking outside the popup in its shadow margin, and operation near the bottom/right screen edges.
- **Tailscale:** the real panel and service consumed synthetic CLI status. Keyboard navigation opened the copy popup; selecting its DNS entry replaced a clipboard sentinel with the exact expected value. Selection and Escape removed both the popup and its shadow, verified against captures of the underlying surface.
- **Wi-Fi QR:** the real QR and password helpers consumed synthetic NetworkManager fields and used the installed `qrencode`. The captured QR decoded to the expected synthetic network at both scales. Revealing the password did not change QR pixels; reopening reset the reveal. Escape and outside clicks dismissed the overlay.
- **Bar-owned tooltip:** the actual keyboard-layout widget exposed the native tooltip. Live shadow enable/disable changed the shadow without changing the bar's reserved desktop area. The bar itself remained shadow-free.

Screenshots were inspected, including fractional-scale popup edges, copy-menu dismissal, QR readability, password reveal, and tooltip enable/disable. No shadow QML binding/type errors appeared in the runtime logs.

These are UI integration tests with synthetic network data, not tests of joining a physical Wi-Fi network or authenticating a real Tailscale account. The unrelated network widget was temporarily removed from the VM test layout after its connectivity checks produced authorization prompts that stole keyboard focus.

The committed shadow acceptance script was rerun successfully at both scales after the follow-up work. Previous coverage of menu, clipboard, emojis, notifications, lock preview, polkit, OSD, gallery controls, native PopupCard, and transitions remains applicable; production QML did not change during this follow-up.

## Full-suite comparison

Clean candidate and unchanged-base archives were tested in the same VM with a scratch directory outside either checkout's path prefix.

- Candidate: 254 shell test files, 9 failing, 17 containing skipped checks.
- Base: 252 shell test files, the same 9 failing, 16 containing skipped checks.
- Both CLI runs fail at `vscode generated theme references current theme file`.
- Failed shell files and emitted failed-assertion messages match exactly between candidate and base.

The failing shell files are `ascii`, `branding-about-animation`, `config`, `kernel-headers-migration`, `mise-work-path`, `omarchy-kernel-migration`, `snapper`, `unowned-system-paths`, and `windows-vm-mount-boundary`. Several require a sibling packaging checkout that is absent from the VM. The full suite is not green; there are no candidate-only failures in this comparison.

The extra candidate skip is the optional offscreen test because PySide6 is absent from the VM. That test was run separately on the host, without starting a desktop shell, and passed five consecutive runs after the harness stabilization described below. Shadow geometry/parser tests, border geometry, QML text-format checks, shell syntax, and `git diff --check` also pass.

### Plymouth discrepancy resolved

The earlier test used a proof directory whose name began with the candidate checkout's name: `...-pr` is a prefix of `...-proof`. The test's fake `stat` marks every path beginning with the checkout root as user-owned. It therefore also marked its own proof-directory scratch paths as untrusted, causing an earlier refusal than the assertion expected.

A four-way rerun confirmed the cause: candidate with prefix-colliding scratch fails; candidate with separate scratch passes; unchanged base passes with either scratch directory. No Plymouth source change is needed.

### Offscreen harness stabilization

A final rerun exposed an intermittent hang while the PySide6 offscreen fixture removed its shadow Loader. Its synchronous `grabWindow()` checks now explicitly use `QSG_RENDER_LOOP=basic` instead of the threaded render loop. All five rendering assertions passed in five consecutive runs. This changes only the test process; the live shell continues to use its normal threaded renderer.

## Performance comparison

Environment: 8-vCPU / 8-GiB QEMU VM, Mesa virgl/OpenGL backed by an AMD Radeon RX 6600 XT, 1920×1080 at 1.25× and 60 Hz. This is **not a low-end physical-GPU benchmark**.

Workload: the real audio panel, 60 timed open/close cycles per fresh shell process, after eight warm-up cycles. Three runs per state, interleaved as off/on/on/off/off/on: 360 timed cycles total. Enabled shadows used alpha 0.6, blur 24, spread 0, offset (0, 6).

| Measurement | Shadows off | Shadows on |
| --- | ---: | ---: |
| Mean wall time for 60 cycles | 33.81 s | 33.80 s |
| Mean shell CPU time | 5.41 s | 5.95 s |
| Per-run 95th-percentile Qt render-work time | 0 ms | 1 ms |
| Per-run 95th-percentile frame time, including swap | 15–16 ms | 16 ms |
| Maximum observed frame time | 17 ms | 19 ms |
| Mean QEMU graphics-engine busy time | 0.670 s | 0.691 s |
| Mean ending shell proportional memory | 369.4 MiB | 379.4 MiB |
| Mean ending QEMU resident VRAM | 364.1 MiB | 374.3 MiB |

Qt timings have millisecond resolution and are CPU-side measurements, not direct GPU timestamps. GPU counters come from the QEMU process's unique DRM clients and include the guest compositor and the rest of the VM. Memory varied between fresh processes, so the roughly 10-MiB differences are workload observations, not fixed per-shadow allocation costs.

The enabled, stationary audio panel accumulated zero shell CPU ticks over a separate ten-second idle observation. The short repeated-cycle runs did not show consistent monotonic memory growth; they are not a long-duration leak test.

Low-end physical hardware, extreme shadow parameters, and many simultaneous large surfaces remain outside this benchmark's coverage. No universal frame-rate or memory guarantee is claimed.

## Restoration

The candidate shell was stopped and the installed shell resumed. Verified restoration of the original shell configuration, absent user `shell.toml`, keyboard layout, rounding, monitor dimensions/scale, and reserved desktop area. The host shell was not changed. The PR remains a draft.
