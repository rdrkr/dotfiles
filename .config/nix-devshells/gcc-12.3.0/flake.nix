{
  description = "GCC 12.3.0 development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/a9858885e197f984d92d7fe64e9fff6b2e488d40";

  outputs = { self, nixpkgs }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };

    # Fontconfig config exposing the fonts the map text engine needs. The DWG
    # label text is rasterized through Qt (QFont/QPainter) -> fontconfig, so
    # glyph coverage depends on what fontconfig can see. DejaVu covers Latin/
    # Greek; HanaMin (hanazono) covers CJK incl. Extension B (e.g. U+2000B),
    # which no default font here has -> otherwise those glyphs render as tofu.
    fontsConf = pkgs.makeFontsConf {
      fontDirectories = [
        pkgs.dejavu_fonts
        pkgs.hanazono
      ];
    };

    # Shared libraries the nix-built Qt 6 app needs at *runtime*. The binary
    # uses nix's dynamic loader, so these must be on LD_LIBRARY_PATH (see the
    # shellHook). Their own transitive deps resolve via each store path's
    # rpath, so only the direct libs need listing here.
    runtimeLibs = with pkgs; [
      # GL / EGL (libglvnd provides libGL.so.1, libEGL.so.1, libGLX.so.0)
      libGL
      libGLU
      # Mesa: the actual GL implementation behind glvnd. `mesa` has libgbm/
      # libglapi; `mesa.drivers` has the DRI drivers (swrast/llvmpipe, d3d12)
      # plus the glvnd vendor libs (libEGL_mesa.so.0) and egl_vendor.d. On
      # WSLg, GLX does not work for a nix binary, so we drive GL through EGL
      # with software llvmpipe (see the shellHook env vars).
      mesa
      mesa.drivers
      # Core system libs reported missing by ldd
      fontconfig
      freetype
      dbus
      glib            # libglib-2.0, libgthread-2.0
      krb5            # libgssapi_krb5
      libpulseaudio   # libpulse
      libxkbcommon
      zstd
      zlib
      # Qt 6 xcb platform plugin (libqxcb.so) is dlopened, so its deps do not
      # show up in `ldd app_topcon`; add the full xcb/X set up front.
      xorg.libX11
      xorg.libXext
      xorg.libXrender
      xorg.libXi
      xorg.libXfixes
      xorg.libXcursor
      xorg.libXrandr
      xorg.libSM
      xorg.libICE
      xorg.libxcb
      xorg.xcbutil
      xorg.xcbutilcursor
      xorg.xcbutilimage
      xorg.xcbutilkeysyms
      xorg.xcbutilrenderutil
      xorg.xcbutilwm
    ];
  in {
    devShells.${system}.default = pkgs.mkShell {
      packages = [
        pkgs.gcc12
        pkgs.cmake
        pkgs.ninja
        # Capturing and driving the app's window on the WSLg X display, so a
        # rendering defect can be observed frame by frame: imagemagick's
        # `import` grabs a window, xdotool clicks and drags in it.
        pkgs.imagemagick
        pkgs.xdotool
        # WSLg's XWayland server restarts unpredictably here, which kills a long
        # GUI session mid-test. Xvfb gives a private X server at a resolution we
        # choose, stable for the whole run and still capturable with `import`.
        pkgs.xorg.xorgserver
        pkgs.xorg.xdpyinfo
        pkgs.xorg.xrandr
        # Let a human watch and drive the app running on that private X server:
        # x11vnc exports the display, websockify+noVNC put it in a browser, so no
        # VNC client needs installing on the Windows side.
        pkgs.x11vnc
        pkgs.novnc
        pkgs.python3Packages.websockify
      ];

      # OpenGL / zlib so the linker can resolve -lGL / -lGLU / -lz at build
      # time. buildInputs (not packages) is what makes the nix cc/ld wrapper
      # inject the -L search path via NIX_LDFLAGS.
      buildInputs = [
        pkgs.libGL
        pkgs.libGLU
        pkgs.zlib
      ];

      shellHook = ''
        # GCC 12 + Qt 6 templates + nix's fortified glibc 2.39 headers emit
        # bogus stringop-overflow/array-bounds/stringop-overread warnings.
        # The project builds with -Werror, so downgrade these known false
        # positives back to warnings (still visible, non-fatal). The nix cc
        # wrapper appends NIX_CFLAGS_COMPILE after the project's -Werror, so
        # these win.
        export NIX_CFLAGS_COMPILE="''${NIX_CFLAGS_COMPILE:-} -Wno-error=stringop-overflow -Wno-error=array-bounds -Wno-error=stringop-overread"

        # Runtime shared libs for the nix-built Qt app. run_mct_linux.sh
        # appends the existing LD_LIBRARY_PATH after its own entries, so these
        # nix libs fill the gaps the app's bundled/system libs don't cover.
        export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath runtimeLibs}''${LD_LIBRARY_PATH:+:''$LD_LIBRARY_PATH}"

        # OpenGL on WSLg for the nix-built app. GLX cannot negotiate an
        # FBConfig here, so route Qt's xcb plugin through EGL instead, backed
        # by Mesa's software llvmpipe driver (proven to give an OpenGL ES 3.2 /
        # GL 4.6 context on this host). This is what lets the app's 3DEngine
        # obtain a valid GL context instead of asserting at startup.
        export LIBGL_ALWAYS_SOFTWARE=1
        export GALLIUM_DRIVER=llvmpipe
        export LIBGL_DRIVERS_PATH="${pkgs.mesa.drivers}/lib/dri"
        export __EGL_VENDOR_LIBRARY_DIRS="${pkgs.mesa.drivers}/share/glvnd/egl_vendor.d"
        export QT_XCB_GL_INTEGRATION=xcb_egl

        # Point fontconfig at the config that includes HanaMin so the map text
        # engine can resolve CJK (incl. Extension B) glyphs instead of tofu.
        export FONTCONFIG_FILE=${fontsConf}

        echo "GCC 12.3.0 dev environment activated"
        gcc --version | head -1
      '';
    };
  };
}
