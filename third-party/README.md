# Third-party notices

The Windows build of Super Booster uses dynamically linked Qt 6.8.3 libraries. Copyright (C) The Qt Company Ltd. and other contributors. The Qt libraries are provided under the GNU Lesser General Public License version 3. The [LGPL version 3](LGPL-3.0.txt) and [GPL version 3](GPL-3.0.txt) texts accompany this build.

## Qt source and attributions

The Qt Project provides corresponding source for Qt 6.8.3 in its [official source archive](https://download.qt.io/archive/qt/6.8/6.8.3/submodules/). The individual archives are available without charge.

| Module | Official source archive | Build metadata and additional notices |
| --- | --- | --- |
| Qt Base | [qtbase 6.8.3](https://download.qt.io/archive/qt/6.8/6.8.3/submodules/qtbase-everywhere-src-6.8.3.tar.xz) | [SBOM](qt/qtbase-6.8.3.spdx) · [binary build revision](https://github.com/qt/qtbase/tree/c07c2d5a527a644d36e7853d55132ae38921682f) |
| Qt Declarative | [qtdeclarative 6.8.3](https://download.qt.io/archive/qt/6.8/6.8.3/submodules/qtdeclarative-everywhere-src-6.8.3.tar.xz) | [SBOM](qt/qtdeclarative-6.8.3.spdx) · [binary build revision](https://github.com/qt/qtdeclarative/tree/2ec235a2235a119887683e55787b93f99dc5f12f) |
| Qt SVG | [qtsvg 6.8.3](https://download.qt.io/archive/qt/6.8/6.8.3/submodules/qtsvg-everywhere-src-6.8.3.tar.xz) | [SBOM](qt/qtsvg-6.8.3.spdx) · [binary build revision](https://github.com/qt/qtsvg/tree/c75099a75e81df35e7347a65e301bbf1011831a5) |
| Qt Shader Tools | [qtshadertools 6.8.3](https://download.qt.io/archive/qt/6.8/6.8.3/submodules/qtshadertools-everywhere-src-6.8.3.tar.xz) | [SBOM](qt/qtshadertools-6.8.3.spdx) · compiles the application's shaders at build time |
| Qt WebSockets | [qtwebsockets 6.8.3](https://download.qt.io/archive/qt/6.8/6.8.3/submodules/qtwebsockets-everywhere-src-6.8.3.tar.xz) | [SBOM](qt/qwebsockets-6.8.3.spdx) |

Qt's archives include their license files and source notices. The [Qt 6.8 third-party credits](https://doc.qt.io/qt-6.8/licenses-used-in-qt.html) provide an additional index by module.

### Using modified Qt libraries

You may modify and replace the LGPL-covered Qt libraries and reverse engineer the application to debug those modifications. Quit Super Booster from its tray menu before replacing files. The installer puts Qt DLLs next to `super_booster.exe` in `%LOCALAPPDATA%\Programs\Super Booster` by default. Keep a backup and replace the Qt DLLs and any matching plugins or QML modules with ABI-compatible Windows x64 MinGW builds in the same relative paths, then restart Super Booster. The shipped Qt binaries were built with MinGW GCC 13.1.0. A custom installation uses the folder selected during setup.

## MinGW-w64 and GCC runtime

`libgcc_s_seh-1.dll` and `libstdc++-6.dll` come from GCC 13.1.0 and are distributed under GPL version 3 with the [GCC Runtime Library Exception version 3.1](mingw/GCC-Runtime-Library-Exception-3.1.txt). The MinGW-w64 runtime and `libwinpthread-1.dll` carry their own [runtime notices](mingw/MinGW-w64-runtime.txt) and [winpthreads license](mingw/winpthreads-COPYING.txt).

Source is available from the [GCC 13.1.0 archive](https://ftp.gnu.org/gnu/gcc/gcc-13.1.0/gcc-13.1.0.tar.xz), the [MinGW-w64 v11 source archive](https://sourceforge.net/projects/mingw-w64/files/mingw-w64/mingw-w64-release/mingw-w64-v11.0.0.tar.bz2/download), and the [MinGW-builds release](https://github.com/niXman/mingw-builds-binaries/releases/tag/13.1.0-rt_v11-rev1). The [MinGW-builds source repository](https://github.com/niXman/mingw-builds) provides its build scripts and GCC patches.

## Rust

The Rust standard library is available under the [MIT](rust/Rust-LICENSE-MIT.txt) or [Apache License 2.0](rust/Rust-LICENSE-APACHE.txt). See the [Rust source](https://github.com/rust-lang/rust) for additional notices. The project's `audio_core/Cargo.lock` identifies its dependency versions. The [Rust notices directory](rust/) contains the text supplied by each crate used for the Windows x64 GNU build, including code-generation dependencies and the Unicode license included by `unicode-ident`.
