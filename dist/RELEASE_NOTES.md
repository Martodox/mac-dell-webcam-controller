## Install

Open the DMG and double-click **Dell camera.prefPane**. Requires macOS 14 or later.

## Changes

- fix(build): don't pipe codesign into grep -q in release checks
- ci: publish the committed DMG as a GitHub release
- build: add local release script
- build: target macOS 14 and make release builds notarizable
- fix(build): re-sign the pane after embedding the agent
- fix(agent): use a standard window for the preview
- feat(pane): rename to "Dell camera" and add an icon
- feat(pane): add System Settings preference pane
- feat(agent): add Dell Camera Agent
- feat(camerakit): control the Dell WB7022 over UVC
- chore: add gitignore
