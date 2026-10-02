# opencomposite

GameNative's build of [OpenComposite](https://gitlab.com/znixian/OpenOVR) for OpenVR games running under Wine on Quest.

Every release is built by GitHub Actions on a Windows runner from the upstream commit in `UPSTREAM_COMMIT` with the patches in `patches/` applied. The GameNative app downloads `opencomposite_x64.dll` from a pinned release and verifies its SHA-256, so the shipped binary always traces back to a CI run.

## Patches

- `background-support.patch`: on Windows, `VR_Init` with `VRApplication_Background` returns `VRInitError_Init_NoServerForBackgroundApp` instead of aborting. GameNative embeds OpenComposite in each Wine process and has no shared vrserver, so helper processes that use the background app type must not open a competing OpenXR session. Also adds the `<chrono>` include current MSVC needs to compile `XrHMD.cpp`.

## Releasing

1. Change `UPSTREAM_COMMIT` or `patches/` as needed and merge to `main`. Every push builds and uploads the DLL as a workflow artifact.
2. Tag the commit: `git tag v1 && git push origin v1`. The workflow builds again and publishes a GitHub release with the DLL and its `.sha256`.
3. Point the GameNative staging scripts at the release URL and update the pinned hash.

## Building locally

Needs Windows, Visual Studio 2022 with the C++ workload, CMake, Git, and the Vulkan SDK.

```powershell
.\build.ps1 -VulkanSdk C:\VulkanSDK\1.3.296.0
```

Output lands in `build\out\`. MSVC builds are not bit-for-bit reproducible across machines, so a local hash will not match the release hash. Ship the release one.

## License

OpenComposite is GPL-3.0. The binaries in releases are built from the pinned upstream commit plus the patches in this repository, which together are the corresponding source.

## XRGame Native: experimental OpenVR 2.15.6 ABI

The `feature/malos/xrgame-sbs-openvr26` branch adds System 026, Applications 008,
Compositor 029, Overlay 028 and Input 011 for current OpenVR clients. It remains
opt-in. The default recipe still builds the reviewed v2 source set.

```powershell
.\build.ps1 -VulkanSdk C:\VulkanSDK\1.3.296.0 -EnableSystem026 -Version xrgame-openvr2156
```

`vendor/openvr-2.15.6` contains the unmodified Valve SDK header and BSD license,
with its upstream/fork commit and checksum in `SOURCE.md`. New vtables use their
actual SDK method order; newer interfaces are never aliased to older vtables.
The generator supports scoped enums and rebuilds when interface declarations
change. The Chaperone perimeter setter accepts the newer const pointer.

Optional eye tracking/distortion, subview overlays, shared submit textures and
cross-process application registration explicitly report unavailable/errors.
The bridge continues to use its existing OpenXR Submit path. Capability queries
return InterfaceNotFound for unknown interfaces instead of aborting the process;
VR_IsInterfaceVersionValid uses the generated interface list. VRControlPanel and
VRHeadsetView exports bind to their existing 006/001 implementations, as required
by Alyx's original client DLL.

Windows/MSVC full Release builds passed on 2026-10-02. The internal candidate's
binary, source and toolchain pins are recorded by the parent repository in
`tools/xrgame/opencomposite-pin.json`. This local build uses VS 2022/MSVC 19.44,
Windows SDK 10.0.26100.0 and the source-pinned Vulkan headers/import definition
from the shadPS4 checkout. The import library can be made with
`lib.exe /machine:x64 /def:vulkan-1.def /out:vulkan-1.lib`; it does not require
executing a Vulkan driver on the Windows build host. Wine supplies runtime Vulkan.

Header checks cover concrete System/Applications/Compositor/Overlay/Input
classes and event/pose sizes. The command after header/stub generation is:

```sh
x86_64-w64-mingw32-clang++ -std=c++20 -fsyntax-only \
  -I <directory-containing-generated> -I <source>/OpenOVR \
  -I <source>/OpenVRHeaders -I <source>/libs/openxr-sdk/include \
  -I <source>/libs/glm tests/system026_abi.cpp
```

Device evidence belongs to the parent repository's SBS validation record.
Compilation and interface availability alone do not establish playable Alyx or
complete implementation of all optional OpenVR features. The maintenance branch
contains the source recipe; the experimental payload has no public binary release.
